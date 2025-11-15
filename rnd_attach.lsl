// Random Attachment Experience Controller
// Loads all object inventory items, listens for AVsitter link messages to obtain
// the active avatar UUID, and rezzes temporary attachments at a regular interval.

integer gDebugEnabled    = FALSE;
integer gDebugChannel    = -982345;   // Owner chat channel for debug commands
integer gDebugListener   = 0;

integer gPendingRez      = FALSE;
float   gRezRequestTime  = 0.0;

float   PENDING_REZ_TIMEOUT = 10.0;

float   SWITCH_INTERVAL = 15.0;     // seconds before requesting a detach
float   MIN_REZ_INTERVAL = 1.5;     // throttle between detach and the next rez
vector  REZ_OFFSET      = <0.0, 0.0, 1.0>;

string  gDetachMessage  = "";

list    gObjects = [];
key     gAvatar = NULL_KEY;
string  gCurrentItem = "";
integer gBaseLinkCount = 0;
key     gActiveRez = NULL_KEY;
integer gActiveChannel = 0;
list    gSitters = [];
float   gLastRezTime = 0.0;

integer ACTION_NONE   = 0;
integer ACTION_REZ    = 1;
integer ACTION_DETACH = 2;

integer gNextAction = ACTION_NONE;

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

key find_key_in_text(string value)
{
    string trimmed = llStringTrim(value, STRING_TRIM);
    if (trimmed == "" || trimmed == "NULL_KEY")
    {
        return NULL_KEY;
    }

    if (is_valid_key(trimmed))
    {
        return (key)llToLower(trimmed);
    }

    list tokens = llParseString2List(trimmed, ["|", ",", ";", " ", "\n", "\t"], []);
    integer len = llGetListLength(tokens);
    integer i;
    for (i = 0; i < len; ++i)
    {
        string token = llStringTrim(llList2String(tokens, i), STRING_TRIM);
        if (is_valid_key(token))
        {
            return (key)llToLower(token);
        }
    }

    return NULL_KEY;
}

key extract_avatar(integer num, string str, key id)
{
    key candidate = find_key_in_text((string)id);
    if (candidate != NULL_KEY)
    {
        return candidate;
    }

    candidate = find_key_in_text(str);
    if (candidate != NULL_KEY)
    {
        return candidate;
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

detach_current(integer resetPending)
{
    if (gCurrentItem != "")
    {
        log("Detaching current item '" + gCurrentItem + "'.");
    }

    if (gActiveRez != NULL_KEY && gActiveChannel != 0)
    {
        if (gDetachMessage == "")
        {
            gDetachMessage = llList2Json(JSON_OBJECT, ["DETACH", JSON_TRUE]);
        }
        llRegionSayTo(gActiveRez, gActiveChannel, gDetachMessage);
        log("Requested detach for " + gCurrentItem);
    }

    gActiveRez = NULL_KEY;
    gActiveChannel = 0;
    gCurrentItem = "";

    if (resetPending)
    {
        gPendingRez = FALSE;
        gRezRequestTime = 0.0;
        gLastRezTime = 0.0;
    }
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
            detach_current(TRUE);
            cancel_scheduled_action();
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

string action_to_string(integer action)
{
    if (action == ACTION_REZ) return "rez";
    if (action == ACTION_DETACH) return "detach";
    return "none";
}

cancel_scheduled_action()
{
    if (gNextAction != ACTION_NONE)
    {
        log("Cancelling scheduled " + action_to_string(gNextAction) + " action.");
    }
    gNextAction = ACTION_NONE;
    llSetTimerEvent(0.0);
}

schedule_action(integer action, float delay)
{
    gNextAction = action;
    llSetTimerEvent(delay);
    log("Scheduled " + action_to_string(action) + " action in " + (string)delay + " seconds.");
}

perform_action(integer action)
{
    if (action == ACTION_NONE)
    {
        log("No scheduled action to perform; ignoring timer event.");
        return;
    }

    if (action == ACTION_DETACH)
    {
        if (gPendingRez)
        {
            float elapsed = llGetTime() - gRezRequestTime;
            if (PENDING_REZ_TIMEOUT > 0.0 && elapsed < PENDING_REZ_TIMEOUT)
            {
                float remaining = PENDING_REZ_TIMEOUT - elapsed;
                log("Detachment delayed while awaiting rez completion (" + (string)remaining + "s remaining).");
                schedule_action(action, remaining);
                return;
            }

            if (PENDING_REZ_TIMEOUT > 0.0 && elapsed >= PENDING_REZ_TIMEOUT)
            {
                log("Pending rez timed out before detach; resetting state.");
                gPendingRez = FALSE;
                gActiveRez = NULL_KEY;
                gActiveChannel = 0;
                gCurrentItem = "";
                gRezRequestTime = 0.0;
                gLastRezTime = 0.0;
            }
            else
            {
                log("Detachment delayed while rez is pending.");
                schedule_action(action, 1.0);
                return;
            }
        }

        log("Detaching current item prior to next rez.");
        detach_current(FALSE);

        if (gAvatar != NULL_KEY)
        {
            if (MIN_REZ_INTERVAL > 0.0)
            {
                schedule_action(ACTION_REZ, MIN_REZ_INTERVAL);
            }
            else
            {
                perform_action(ACTION_REZ);
            }
        }
        return;
    }

    if (action == ACTION_REZ)
    {
        if (gAvatar == NULL_KEY)
        {
            log("Rez action skipped because no avatar is active.");
            return;
        }

        if (gPendingRez)
        {
            float elapsedRez = llGetTime() - gRezRequestTime;
            log("Rez action skipped; previous rez still pending (" + (string)elapsedRez + "s elapsed).");
            float retryDelay = MIN_REZ_INTERVAL;
            if (retryDelay <= 0.0)
            {
                retryDelay = 1.0;
            }
            schedule_action(ACTION_REZ, retryDelay);
            return;
        }

        if (gLastRezTime > 0.0 && MIN_REZ_INTERVAL > 0.0)
        {
            float sinceLast = llGetTime() - gLastRezTime;
            if (sinceLast < MIN_REZ_INTERVAL)
            {
                float remainingDelay = MIN_REZ_INTERVAL - sinceLast;
                log("Rez action deferred to respect throttle (" + (string)remainingDelay + "s remaining).");
                schedule_action(ACTION_REZ, remainingDelay);
                return;
            }
        }

        rez_random_item();
        return;
    }

    log("Unknown scheduled action " + (string)action + "; ignoring.");
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

    float now = llGetTime();

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

    gCurrentItem = choice;
    gActiveChannel = random_channel();
    vector rezPos = llGetPos() + (REZ_OFFSET * llGetRot());
    rotation rezRot = llGetRot();

    log("Rezzing " + choice + " for avatar " + (string)gAvatar + " on channel " + (string)gActiveChannel);
    llRezAtRoot(choice, rezPos, ZERO_VECTOR, rezRot, gActiveChannel);
    gPendingRez = TRUE;
    gRezRequestTime = now;
    gLastRezTime = now;

    if (SWITCH_INTERVAL > 0.0)
    {
        schedule_action(ACTION_DETACH, SWITCH_INTERVAL);
    }
    else
    {
        log("Switch interval non-positive; automatic detach scheduling disabled.");
    }
}

start_cycle()
{
    if (gAvatar == NULL_KEY)
    {
        log("Start cycle requested without an avatar; ignoring.");
        return;
    }

    log("Starting attachment cycle for avatar " + (string)gAvatar + ".");

    if (gPendingRez)
    {
        log("Cycle already running; a rez request is pending.");
        return;
    }

    if (gActiveRez != NULL_KEY)
    {
        log("Cycle already running; an attachment is currently active.");
        return;
    }

    if (gNextAction != ACTION_NONE)
    {
        log("Cycle already scheduled; next action is " + action_to_string(gNextAction) + ".");
        return;
    }

    perform_action(ACTION_REZ);
}

stop_cycle()
{
    log("Stopping attachment cycle.");
    cancel_scheduled_action();
    detach_current(TRUE);
    gAvatar = NULL_KEY;
}

// --- State -------------------------------------------------------------------

default
{
    state_entry()
    {
        refresh_inventory();
        cancel_scheduled_action();
        gBaseLinkCount = llGetNumberOfPrims();
        clear_all_sitters();
        detach_current(TRUE);
        gPendingRez = FALSE;
        gRezRequestTime = 0.0;
        gLastRezTime = 0.0;
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
            cancel_scheduled_action();
            detach_current(TRUE);
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
                detach_current(TRUE);
                cancel_scheduled_action();
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
        integer action = gNextAction;
        gNextAction = ACTION_NONE;
        llSetTimerEvent(0.0);
        log("Timer event fired for scheduled " + action_to_string(action) + " action.");
        perform_action(action);
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
            detach_current(TRUE);
            return;
        }

        if (gAvatar == NULL_KEY)
        {
            log("No avatar active during rez; detaching.");
            detach_current(TRUE);
            return;
        }

        string message = llList2Json(JSON_OBJECT, ["AVI_UUID", (string)gAvatar]);
        llRegionSayTo(gActiveRez, gActiveChannel, message);
        log("Sent attach request to rezzed object " + (string)gActiveRez);
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
