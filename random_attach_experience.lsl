// Random Attachment Experience Controller
// Loads all object inventory items, listens for AVsitter link messages to obtain
// the active avatar UUID, requests experience permissions, and cycles attachments
// at a regular interval.

integer DEBUG_LOG = TRUE;

float   SWITCH_INTERVAL = 15.0;     // seconds between attachment swaps
integer ATTACH_POINT    = ATTACH_CHEST;

list    gObjects = [];
key     gAvatar = NULL_KEY;
key     gPendingAgent = NULL_KEY;
integer gHasPerms = FALSE;
string  gCurrentItem = "";
integer gBaseLinkCount = 0;

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
    if (gCurrentItem != "")
    {
        llDetachFromAvatar();
        log("Detached " + gCurrentItem);
        gCurrentItem = "";
    }
}

attach_random_item()
{
    integer count = llGetListLength(gObjects);
    if (!gHasPerms || gAvatar == NULL_KEY || count == 0)
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
    llAttachToAvatarTemp(ATTACH_POINT);
    log("Attached " + choice + " to avatar " + (string)gAvatar);
}

start_cycle()
{
    if (!gHasPerms)
    {
        return;
    }

    attach_random_item();
    if (SWITCH_INTERVAL > 0.0)
    {
        llSetTimerEvent(SWITCH_INTERVAL);
    }
}

stop_cycle()
{
    llSetTimerEvent(0.0);
    detach_current();
    gHasPerms = FALSE;
    gAvatar = NULL_KEY;
}

request_permissions(key agent)
{
    if (agent == NULL_KEY)
    {
        return;
    }

    if (agent == gAvatar && gHasPerms)
    {
        start_cycle();
        return;
    }

    log("Requesting experience permissions for " + (string)agent);
    gPendingAgent = agent;
    llRequestExperiencePermissions(agent, "Attachment control");
}

// --- State -------------------------------------------------------------------

default
{
    state_entry()
    {
        refresh_inventory();
        llSetTimerEvent(0.0);
        gBaseLinkCount = llGetNumberOfPrims();
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
                gAvatar = id;
                log("Sitter detected via link message " + (string)num + ": " + str);
                request_permissions(gAvatar);
            }
            return;
        }

        key agent = extract_avatar(num, str, id);
        if (agent != NULL_KEY)
        {
            gAvatar = agent;
            request_permissions(agent);
            return;
        }

        if (gAvatar != NULL_KEY && is_unsit_message(str))
        {
            log("Unsit message received; stopping cycle.");
            stop_cycle();
        }
    }

    experience_permissions(key agent)
    {
        if (agent != gPendingAgent)
        {
            return;
        }

        log("Permissions granted for " + (string)agent);
        gAvatar = agent;
        gHasPerms = TRUE;
        start_cycle();
    }

    experience_permissions_denied(key agent, integer reason)
    {
        if (agent != gPendingAgent)
        {
            return;
        }

        log("Permissions denied for " + (string)agent + " reason " + (string)reason);
        stop_cycle();
    }

    timer()
    {
        attach_random_item();
    }
}
