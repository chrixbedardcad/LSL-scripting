// Attach permission handler for rezzed attachments
// Requests experience permissions from the provided avatar and attaches
// temporarily, detaching and cleaning up when requested by the rezzer.

integer gDebugEnabled   = FALSE;
integer gDebugChannel   = -982345;    // Owner chat channel for debug commands
integer gDebugListener  = 0;

integer gListener = 0;
integer gChannel = 0;
key     gTarget = NULL_KEY;
integer gAttachPoint = ATTACH_CHEST;
float   gTimeout = 60.0;

integer gPermissionAttempts = 0;
integer gMaxPermissionAttempts = 5;
float   gPermissionRetryDelay = 1.5;
integer gPendingPermission = FALSE;
float   gNextPermissionAttempt = 0.0;

float   gExpireTime = 0.0;
float   gTimerInterval = 0.0;

log(string msg)
{
    if (gDebugEnabled)
    {
        llOwnerSay("[AttachPerm] " + msg);
    }
}

configure_debug(integer enable, string reason)
{
    if (enable == gDebugEnabled)
    {
        string debugState;
        if (enable)
        {
            debugState = "enabled";
        }
        else
        {
            debugState = "disabled";
        }
        llOwnerSay("[AttachPerm] Debug already " + debugState + " (" + reason + ")");
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
    llOwnerSay("[AttachPerm] Debug " + debugState + " (" + reason + ")");
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

listen_handle()
{
    if (gListener)
    {
        llListenRemove(gListener);
        gListener = 0;
        log("Existing rezzer listener removed.");
    }

    if (gChannel != 0)
    {
        gListener = llListen(gChannel, "", NULL_KEY, "");
        log("Listening for rezzer commands on channel " + (string)gChannel + ".");
    }
    else
    {
        log("Rezzer channel not configured; listener disabled.");
    }
}

ensure_timer()
{
    float desired = 0.0;
    float now = llGetTime();

    if (gPendingPermission)
    {
        float remaining = gNextPermissionAttempt - now;
        if (remaining < 0.1)
        {
            remaining = 0.1;
        }
        desired = remaining;
    }

    if (gExpireTime > 0.0)
    {
        float remaining = gExpireTime - now;
        if (remaining <= 0.0)
        {
            remaining = 0.1;
        }
        if (desired == 0.0 || remaining < desired)
        {
            desired = remaining;
        }
    }

    if (desired != gTimerInterval)
    {
        gTimerInterval = desired;
        llSetTimerEvent(desired);
        if (gDebugEnabled)
        {
            if (desired == 0.0)
            {
                log("Timer disabled.");
            }
            else
            {
                log("Timer scheduled to fire in " + (string)desired + " seconds.");
            }
        }
    }
}

set_expiration(float seconds, string reason)
{
    if (seconds <= 0.0)
    {
        if (gExpireTime != 0.0)
        {
            gExpireTime = 0.0;
            log("Expiration cleared (" + reason + ")");
        }
    }
    else
    {
        gExpireTime = llGetTime() + seconds;
        log("Expiration scheduled in " + (string)seconds + " seconds (" + reason + ")");
    }
    ensure_timer();
}

reset_state()
{
    gTarget = NULL_KEY;
    gAttachPoint = ATTACH_CHEST;
    gPermissionAttempts = 0;
    gPendingPermission = FALSE;
    gNextPermissionAttempt = 0.0;
    set_expiration(gTimeout, "reset_state");
    listen_handle();
    log("State reset with timeout " + (string)gTimeout + " seconds.");
}

cleanup(string reason)
{
    log("Cleanup initiated (" + reason + ").");
    if (llGetAttached())
    {
        log("Detaching from avatar as part of cleanup.");
        llDetachFromAvatar();
    }
    llDie();
}

schedule_permission_retry(string reason)
{
    if (gPermissionAttempts >= gMaxPermissionAttempts)
    {
        log("Maximum permission attempts reached; aborting retries.");
        cleanup("permission attempts exhausted");
        return;
    }

    gPendingPermission = TRUE;
    gNextPermissionAttempt = llGetTime() + gPermissionRetryDelay;
    log("Scheduling permission retry in " + (string)gPermissionRetryDelay + " seconds (" + reason + ")");
    ensure_timer();
}

request_permissions(string reason, integer allowDefer)
{
    if (gTarget == NULL_KEY)
    {
        log("Permission request aborted because no target avatar is set.");
        return;
    }

    if (gPermissionAttempts >= gMaxPermissionAttempts)
    {
        log("Permission attempts exhausted before new request.");
        cleanup("permission attempts exhausted");
        return;
    }

    integer info = llGetAgentInfo(gTarget);
    log("Preparing permission request attempt " + (string)(gPermissionAttempts + 1) +
        " (reason: " + reason + ") agentInfo=" + (string)info + ".");

    if (allowDefer && ((info & AGENT_SITTING) || (info & AGENT_ON_OBJECT)))
    {
        log("Target is seated; deferring permission request.");
        schedule_permission_retry("avatar seated");
        return;
    }

    ++gPermissionAttempts;
    gPendingPermission = FALSE;
    log("Requesting experience permissions from " + (string)gTarget +
        " for attach point " + (string)gAttachPoint + ".");
    llRequestExperiencePermissions(gTarget, "attach");
    ensure_timer();
}

handle_attach_command(key target, integer point)
{
    if (target == NULL_KEY)
    {
        log("Attach command ignored because the avatar key is NULL_KEY.");
        return;
    }

    gTarget = target;
    gAttachPoint = point;
    gPermissionAttempts = 0;
    gPendingPermission = FALSE;
    gNextPermissionAttempt = 0.0;

    log("Attach command received for avatar " + (string)gTarget +
        " on attach point " + (string)gAttachPoint + ".");
    set_expiration(gTimeout, "attach command");
    request_permissions("attach command", TRUE);
}

handle_detach_command()
{
    log("Detach command received from rezzer.");
    cleanup("detach command");
}

integer parse_attach_point(list tokens)
{
    if (llGetListLength(tokens) < 3)
    {
        return ATTACH_CHEST;
    }
    return (integer)llList2String(tokens, 2);
}

default
{
    state_entry()
    {
        update_debug_listener();
        reset_state();
        log("Attach permission handler initialized.");
    }

    on_rez(integer start_param)
    {
        gChannel = start_param;
        log("on_rez received with channel " + (string)gChannel + ".");
        reset_state();
    }

    listen(integer channel, string name, key id, string message)
    {
        if (channel == gDebugChannel && id == llGetOwner())
        {
            if (!handle_debug_command(message))
            {
                llOwnerSay("[AttachPerm] Unrecognized debug command: '" + message + "'.");
            }
            return;
        }

        if (channel != gChannel)
        {
            return;
        }

        string trimmed = llStringTrim(message, STRING_TRIM);
        if (trimmed == "")
        {
            log("Ignoring empty command message.");
            return;
        }

        list tokens = llParseString2List(trimmed, ["|"], []);
        integer length = llGetListLength(tokens);
        string command = llToUpper(llList2String(tokens, 0));

        log("Received command '" + command + "' with payload '" + trimmed + "'.");

        if (command == "ATTACH")
        {
            if (length < 3)
            {
                log("ATTACH command ignored due to insufficient parameters.");
                return;
            }

            key target = (key)llList2String(tokens, 1);
            integer point = parse_attach_point(tokens);
            handle_attach_command(target, point);
        }
        else if (command == "DETACH")
        {
            handle_detach_command();
        }
        else
        {
            log("Unknown command '" + command + "' ignored.");
        }
    }

    experience_permissions(key agent)
    {
        log("Experience permissions granted by " + (string)agent + ".");
        if (agent != gTarget)
        {
            log("Granted permissions do not match current target; ignoring.");
            return;
        }

        gPendingPermission = FALSE;
        gNextPermissionAttempt = 0.0;
        set_expiration(gTimeout, "post-permission attach");
        log("Calling llAttachToAvatarTemp for attach point " + (string)gAttachPoint + ".");
        llAttachToAvatarTemp(gAttachPoint);
    }

    experience_permissions_denied(key agent, integer reason)
    {
        log("Experience permissions denied by " + (string)agent + " reason=" + (string)reason + ".");
        if (agent != gTarget)
        {
            log("Denial received for non-target avatar; ignoring.");
            return;
        }

        schedule_permission_retry("denied reason " + (string)reason);
    }

    attach(key id)
    {
        if (id == NULL_KEY)
        {
            log("Attachment detached; performing cleanup.");
            cleanup("attachment detached");
        }
        else
        {
            log("Attachment now worn by avatar " + (string)id + ".");
            gPendingPermission = FALSE;
            gPermissionAttempts = 0;
            set_expiration(0.0, "attached");
        }
    }

    timer()
    {
        float now = llGetTime();

        if (gPendingPermission && now >= gNextPermissionAttempt)
        {
            log("Permission retry timer reached; attempting again.");
            gPendingPermission = FALSE;
            request_permissions("retry", FALSE);
        }

        if (gExpireTime > 0.0 && now >= gExpireTime)
        {
            log("Timeout reached while waiting for attachment; cleaning up.");
            cleanup("timeout");
            return;
        }

        ensure_timer();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            gDebugEnabled = FALSE;
            update_debug_listener();
            reset_state();
            log("Owner changed; script state reset.");
        }
    }
}
