// Random Attachment Experience Controller
// Loads all object inventory items, listens for AVsitter link messages to obtain
// the active avatar UUID, and rezzes temporary attachments at a regular interval.

integer DEBUG_LOG = TRUE;

float   SWITCH_INTERVAL = 15.0;     // seconds between attachment swaps
integer ATTACH_POINT    = ATTACH_CHEST;
vector  REZ_OFFSET      = <0.0, 0.0, 1.0>;

list    gObjects = [];
key     gAvatar = NULL_KEY;
string  gCurrentItem = "";
integer gBaseLinkCount = 0;
key     gActiveRez = NULL_KEY;
integer gActiveChannel = 0;

// --- Helpers -----------------------------------------------------------------

integer is_valid_key(string value)
{
    if (value == "" || value == "NULL_KEY")
    {
        return FALSE;
    }

    key possible = (key)value;
    if (possible == NULL_KEY)
    {
        return FALSE;
    }

    return (string)possible == llToLower(value) || (string)possible == value;
}

key extract_avatar(integer num, string str, key id)
{
    if (id != NULL_KEY)
    {
        return id;
    }

    if (is_valid_key(str))
    {
        return (key)str;
    }

    list tokens = llParseString2List(str, ["|", ",", ";", " ", "\n", "\t"], []);
    integer len = llGetListLength(tokens);
    integer i;
    for (i = 0; i < len; ++i)
    {
        string token = llList2String(tokens, i);
        if (is_valid_key(token))
        {
            return (key)token;
        }
    }

    return NULL_KEY;
}

integer is_unsit_message(string str)
{
    string upper = llToUpper(str);
    if (llSubStringIndex(upper, "UNSIT") != -1) return TRUE;
    if (llSubStringIndex(upper, "STAND") != -1) return TRUE;
    if (llSubStringIndex(upper, "STOP") != -1) return TRUE;
    return FALSE;
}

log(string msg)
{
    if (DEBUG_LOG)
    {
        llOwnerSay("[RandomAttach] " + msg);
    }
}

refresh_inventory()
{
    gObjects = [];
    integer count = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    for (i = 0; i < count; ++i)
    {
        string name = llGetInventoryName(INVENTORY_OBJECT, i);
        if (name != "")
        {
            gObjects += name;
        }
    }

    log("Inventory refreshed. Objects found: " + (string)llGetListLength(gObjects));
}

detach_current()
{
    if (gActiveRez != NULL_KEY && gActiveChannel != 0)
    {
        llRegionSayTo(gActiveRez, gActiveChannel, "DETACH");
        log("Requested detach for " + gCurrentItem);
    }

    gActiveRez = NULL_KEY;
    gActiveChannel = 0;
    gCurrentItem = "";
}

integer random_channel()
{
    return 100000 + (integer)llFrand(900000.0);
}

rez_random_item()
{
    if (gAvatar == NULL_KEY)
    {
        return;
    }

    integer count = llGetListLength(gObjects);
    if (count == 0)
    {
        return;
    }

    string choice;
    if (count == 1)
    {
        choice = llList2String(gObjects, 0);
    }
    else
    {
        integer maxAttempts = count;
        do
        {
            choice = llList2String(gObjects, (integer)llFrand((float)count));
            --maxAttempts;
        } while (maxAttempts > 0 && choice == gCurrentItem);
    }

    detach_current();

    gCurrentItem = choice;
    gActiveChannel = random_channel();
    vector rezPos = llGetPos() + (REZ_OFFSET * llGetRot());
    rotation rezRot = llGetRot();

    log("Rezzing " + choice + " for avatar " + (string)gAvatar + " on channel " + (string)gActiveChannel);
    llRezAtRoot(choice, rezPos, ZERO_VECTOR, rezRot, gActiveChannel);
}

start_cycle()
{
    if (gAvatar == NULL_KEY)
    {
        return;
    }

    if (gActiveRez == NULL_KEY)
    {
        rez_random_item();
    }

    if (SWITCH_INTERVAL > 0.0)
    {
        llSetTimerEvent(SWITCH_INTERVAL);
    }
    else
    {
        llSetTimerEvent(0.0);
    }
}

stop_cycle()
{
    llSetTimerEvent(0.0);
    detach_current();
    gAvatar = NULL_KEY;
}

// --- State -------------------------------------------------------------------

default
{
    state_entry()
    {
        refresh_inventory();
        llSetTimerEvent(0.0);
        gBaseLinkCount = llGetNumberOfPrims();
        detach_current();
    }

    changed(integer change)
    {
        if (change & CHANGED_INVENTORY)
        {
            refresh_inventory();
        }
        else if (change & CHANGED_LINK)
        {
            // Clear everything if the avatar stands without an explicit message.
            integer linkCount = llGetNumberOfPrims();
            if (linkCount <= gBaseLinkCount && gAvatar != NULL_KEY)
            {
                log("Link change detected; stopping cycle.");
                stop_cycle();
            }
        }
    }

    link_message(integer sender_num, integer num, string str, key id)
    {
        if (num == 90060)
        {
            if (id != NULL_KEY)
            {
                if (gAvatar != id)
                {
                    detach_current();
                }

                gAvatar = id;
                log("Sitter detected via link message " + (string)num + ": " + str);
                start_cycle();
            }
            return;
        }

        key agent = extract_avatar(num, str, id);
        if (agent != NULL_KEY)
        {
            if (gAvatar != agent)
            {
                detach_current();
            }

            gAvatar = agent;
            start_cycle();
            return;
        }

        if (gAvatar != NULL_KEY && is_unsit_message(str))
        {
            log("Unsit message received; stopping cycle.");
            stop_cycle();
        }
    }

    timer()
    {
        rez_random_item();
    }

    object_rez(key id)
    {
        if (id == NULL_KEY)
        {
            return;
        }

        gActiveRez = id;

        if (gActiveChannel == 0)
        {
            return;
        }

        if (gAvatar == NULL_KEY)
        {
            detach_current();
            return;
        }

        string message = "ATTACH|" + (string)gAvatar + "|" + (string)ATTACH_POINT;
        llRegionSayTo(gActiveRez, gActiveChannel, message);
        log("Sent attach command to rezzed object " + (string)gActiveRez);
    }
}
