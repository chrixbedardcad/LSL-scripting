// Random Attachment Experience Controller
// Loads all object inventory items, listens for AVsitter link messages to obtain
// the active avatar UUID, and rezzes temporary attachments at a regular interval.

integer gDebugEnabled    = FALSE;
integer gDebugChannel    = -982345;   // Owner chat channel for debug commands
integer gDebugListener   = 0;

integer gPendingRez      = FALSE;
float   gRezRequestTime  = 0.0;

float   PENDING_REZ_TIMEOUT = 10.0;

float   SWITCH_INTERVAL = 15.0;     // seconds between attachment swaps
integer ATTACH_POINT    = ATTACH_CHEST;
vector  REZ_OFFSET      = <0.0, 0.0, 1.0>;

list    gObjects = [];
key     gAvatar = NULL_KEY;
string  gCurrentItem = "";
integer gBaseLinkCount = 0;
key     gActiveRez = NULL_KEY;
integer gActiveChannel = 0;
list    gSitters = [];

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
        string idString = (string)id;
        if (is_valid_key(idString))
        {
            return (key)idString;
        }

        list idTokens = llParseString2List(idString, ["|", ",", ";", " ", "\n", "\t"], []);
        integer idLen = llGetListLength(idTokens);
        integer idx;
        for (idx = 0; idx < idLen; ++idx)
        {
            string idToken = llList2String(idTokens, idx);
            if (is_valid_key(idToken))
            {
                return (key)idToken;
            }
        }
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
    if (gDebugEnabled)
    {
        llOwnerSay("[RandomAttach] " + msg);
    }
}

configure_debug(integer enable, string reason)
{
    if (enable == gDebugEnabled)
    {
        if (enable)
        {
            llOwnerSay("[RandomAttach] Debug already enabled (" + reason + ")");
        }
        else
        {
            llOwnerSay("[RandomAttach] Debug already disabled (" + reason + ")");
        }
        return;
    }

    gDebugEnabled = enable;
    string debugState;
    if (enable)
    {
        debugState = "enabled";
    }
    else
    {
        debugState = "disabled";
    }
    llOwnerSay("[RandomAttach] Debug " + debugState + " (" + reason + ")");
}

update_debug_listener()
{
    if (gDebugListener)
    {
        llListenRemove(gDebugListener);
        gDebugListener = 0;
    }

    if (gDebugChannel != 0)
    {
        gDebugListener = llListen(gDebugChannel, "", llGetOwner(), "");
    }
}

integer parse_boolean(string value)
{
    string lower = llToLower(llStringTrim(value, STRING_TRIM));
    if (lower == "1" || lower == "true" || lower == "on" || lower == "yes")
    {
        return TRUE;
    }
    if (lower == "0" || lower == "false" || lower == "off" || lower == "no")
    {
        return FALSE;
    }
    return -1;
}

integer handle_debug_command(string message)
{
    string trimmed = llStringTrim(message, STRING_TRIM);
    string lower = llToLower(trimmed);

    if (lower == "debug")
    {
        configure_debug(!gDebugEnabled, "toggle");
        return TRUE;
    }

    list tokens = llParseString2List(lower, [" ", "=", ":"], []);
    if (llGetListLength(tokens) >= 2 && llList2String(tokens, 0) == "debug")
    {
        integer parsed = parse_boolean(llList2String(tokens, 1));
        if (parsed != -1)
        {
            configure_debug(parsed, "command");
            return TRUE;
        }
    }

    return FALSE;
}

refresh_inventory()
{
    log("Refreshing inventory of attachable objects.");
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
        log("Detaching current item '" + gCurrentItem + "'.");
    }

    if (gActiveRez != NULL_KEY && gActiveChannel != 0)
    {
        llRegionSayTo(gActiveRez, gActiveChannel, "DETACH");
        log("Requested detach for " + gCurrentItem);
    }

    gActiveRez = NULL_KEY;
    gActiveChannel = 0;
    gCurrentItem = "";
    gPendingRez = FALSE;
    gRezRequestTime = 0.0;
}

clear_all_sitters()
{
    if (llGetListLength(gSitters) > 0)
    {
        log("Clearing tracked sitters (" + (string)llGetListLength(gSitters) + " entries).");
    }
    gSitters = [];
}

register_sitter(key sitter)
{
    if (sitter == NULL_KEY)
    {
        return;
    }

    integer existing = llListFindList(gSitters, [sitter]);
    if (existing != -1)
    {
        gSitters = llDeleteSubList(gSitters, existing, existing);
    }
    gSitters = [sitter] + gSitters;
    log("Registered sitter " + (string)sitter + ". Active sitters: " + (string)llGetListLength(gSitters));

    if (gAvatar != sitter)
    {
        if (gAvatar != NULL_KEY)
        {
            detach_current();
        }
        gAvatar = sitter;
    }

    start_cycle();
}

handle_sitter_departure(key sitter)
{
    if (sitter == NULL_KEY)
    {
        return;
    }

    integer existing = llListFindList(gSitters, [sitter]);
    if (existing == -1)
    {
        log("Departure received for unknown sitter " + (string)sitter + ".");
        return;
    }

    gSitters = llDeleteSubList(gSitters, existing, existing);
    log("Sitter " + (string)sitter + " removed. Remaining sitters: " + (string)llGetListLength(gSitters));

    if (gAvatar == sitter)
    {
        log("Active sitter stood up; stopping current cycle.");
        stop_cycle();
        if (llGetListLength(gSitters) > 0)
        {
            gAvatar = llList2Key(gSitters, 0);
            log("Switching to next sitter " + (string)gAvatar + ".");
            start_cycle();
        }
    }
}

integer random_channel()
{
    return 100000 + (integer)llFrand(900000.0);
}

rez_random_item()
{
    if (gPendingRez)
    {
        log("Rez request skipped: awaiting completion of pending rez.");
        return;
    }

    if (gAvatar == NULL_KEY)
    {
        log("Rez request ignored because no active avatar is set.");
        return;
    }

    integer count = llGetListLength(gObjects);
    if (count == 0)
    {
        log("Rez request ignored because no inventory objects are available.");
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
    gPendingRez = TRUE;
    gRezRequestTime = llGetTime();
}

start_cycle()
{
    if (gAvatar == NULL_KEY)
    {
        log("Start cycle requested without an avatar; ignoring.");
        return;
    }

    log("Starting attachment cycle for avatar " + (string)gAvatar + ".");

    if (gActiveRez == NULL_KEY && !gPendingRez)
    {
        rez_random_item();
    }

    if (SWITCH_INTERVAL > 0.0)
    {
        llSetTimerEvent(SWITCH_INTERVAL);
        log("Timer scheduled with interval " + (string)SWITCH_INTERVAL + " seconds.");
    }
    else
    {
        llSetTimerEvent(0.0);
        log("Timer disabled because the switch interval is non-positive.");
    }
}

stop_cycle()
{
    log("Stopping attachment cycle.");
    llSetTimerEvent(0.0);
    log("Timer disabled.");
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
        clear_all_sitters();
        detach_current();
        gPendingRez = FALSE;
        gRezRequestTime = 0.0;
        update_debug_listener();
        log("State entry complete. Base link count: " + (string)gBaseLinkCount);
    }

    changed(integer change)
    {
        log("Changed event received with mask " + (string)change + ".");
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
                clear_all_sitters();
            }
        }
        if (change & CHANGED_OWNER)
        {
            gAvatar = NULL_KEY;
            gPendingRez = FALSE;
            gRezRequestTime = 0.0;
            detach_current();
            clear_all_sitters();
            update_debug_listener();
            log("Owner changed; state reset.");
        }
    }

    link_message(integer sender_num, integer num, string str, key id)
    {
        log("Link message received: sender=" + (string)sender_num + " num=" + (string)num + " id=" + (string)id + " msg='" + str + "'.");
        if (num == 90060)
        {
            key sitter = extract_avatar(num, str, id);
            if (sitter != NULL_KEY)
            {
                log("Sitter detected via link message " + (string)num + ": " + str);
                register_sitter(sitter);
            }
            return;
        }

        if (num == 90065)
        {
            key sitter = extract_avatar(num, str, id);
            if (sitter == NULL_KEY)
            {
                sitter = gAvatar;
            }
            log("Stand detected via link message " + (string)num + ": " + str);
            handle_sitter_departure(sitter);
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
            log("Avatar detected via link message: " + (string)gAvatar);
            start_cycle();
            return;
        }

        if (gAvatar != NULL_KEY && is_unsit_message(str))
        {
            log("Unsit message received; stopping cycle.");
            key sitter = extract_avatar(num, str, id);
            if (sitter != NULL_KEY)
            {
                handle_sitter_departure(sitter);
            }
            else
            {
                stop_cycle();
                clear_all_sitters();
            }
        }
    }

    timer()
    {
        log("Timer event fired; attempting to rez next item.");

        if (gPendingRez)
        {
            float elapsed = llGetTime() - gRezRequestTime;
            log("Pending rez detected (" + (string)elapsed + "s elapsed).");
            if (PENDING_REZ_TIMEOUT > 0.0 && elapsed >= PENDING_REZ_TIMEOUT)
            {
                log("Pending rez timed out; resetting state to allow another attempt.");
                gPendingRez = FALSE;
                gActiveRez = NULL_KEY;
                gActiveChannel = 0;
                gCurrentItem = "";
                gRezRequestTime = 0.0;
            }
            else
            {
                return;
            }
        }

        rez_random_item();
    }

    object_rez(key id)
    {
        log("object_rez event fired with id=" + (string)id + ".");
        if (id == NULL_KEY)
        {
            return;
        }

        gActiveRez = id;
        gPendingRez = FALSE;
        gRezRequestTime = 0.0;

        if (gActiveChannel == 0)
        {
            log("No active channel present; detaching current item.");
            detach_current();
            return;
        }

        if (gAvatar == NULL_KEY)
        {
            log("No avatar active during rez; detaching.");
            detach_current();
            return;
        }

        string message = "ATTACH|" + (string)gAvatar + "|" + (string)ATTACH_POINT;
        llRegionSayTo(gActiveRez, gActiveChannel, message);
        log("Sent attach command to rezzed object " + (string)gActiveRez);
    }

    listen(integer channel, string name, key id, string message)
    {
        if (channel == gDebugChannel && id == llGetOwner())
        {
            if (!handle_debug_command(message))
            {
                llOwnerSay("[RandomAttach] Unrecognized debug command: '" + message + "'.");
            }
        }
    }
}
