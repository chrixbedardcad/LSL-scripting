// Attach permission handler for rezzed attachments
// Requests experience permissions from the provided avatar and attaches
// temporarily, detaching and cleaning up when requested by the rezzer.

integer gListener = 0;
integer gChannel = 0;
key     gTarget = NULL_KEY;
integer gAttachPoint = ATTACH_CHEST;
float   gTimeout = 60.0;

listen_handle()
{
    if (gListener)
    {
        llListenRemove(gListener);
        gListener = 0;
    }

    if (gChannel != 0)
    {
        gListener = llListen(gChannel, "", NULL_KEY, "");
    }
}

reset_state()
{
    gTarget = NULL_KEY;
    gAttachPoint = ATTACH_CHEST;
    llSetTimerEvent(gTimeout);
    listen_handle();
}

default
{
    state_entry()
    {
        reset_state();
    }

    on_rez(integer start_param)
    {
        gChannel = start_param;
        reset_state();
    }

    listen(integer channel, string name, key id, string message)
    {
        if (channel != gChannel)
        {
            return;
        }

        list tokens = llParseString2List(message, ["|"], []);
        integer length = llGetListLength(tokens);
        if (length == 0)
        {
            return;
        }

        string command = llToUpper(llList2String(tokens, 0));

        if (command == "ATTACH")
        {
            if (length < 3)
            {
                return;
            }

            key target = (key)llList2String(tokens, 1);
            integer point = (integer)llList2String(tokens, 2);

            if (target == NULL_KEY)
            {
                return;
            }

            gTarget = target;
            gAttachPoint = point;
            llRequestExperiencePermissions(target, "attach");
            llSetTimerEvent(gTimeout);
        }
        else if (command == "DETACH")
        {
            if (llGetAttached())
            {
                llDetachFromAvatar();
            }
            llDie();
        }
    }

    experience_permissions(key agent)
    {
        if (agent != gTarget)
        {
            return;
        }

        llAttachToAvatarTemp(gAttachPoint);
        llSetTimerEvent(gTimeout);
    }

    experience_permissions_denied(key agent, integer reason)
    {
        if (agent != gTarget)
        {
            return;
        }

        llDie();
    }

    attach(key id)
    {
        if (id == NULL_KEY)
        {
            llDie();
        }
        else
        {
            llSetTimerEvent(0.0);
        }
    }

    timer()
    {
        if (llGetAttached())
        {
            llDetachFromAvatar();
        }
        llDie();
    }
}
