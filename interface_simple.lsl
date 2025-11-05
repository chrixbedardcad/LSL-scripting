// interface_simple.lsl -- Minimal start/stop listener.
// Listens on the rez parameter channel and reacts to start/stop commands.

integer gChannel = 0;
integer gListen = 0;
string  gMyName;

integer start_listen()
{
    if (gChannel == 0)
    {
        return FALSE;
    }

    if (gListen)
    {
        llListenRemove(gListen);
    }
    gListen = llListen(gChannel, "", NULL_KEY, "");
    return TRUE;
}

integer accepts_name(string target)
{
    if (target == JSON_INVALID || target == "")
    {
        return TRUE;
    }
    return llToLower(target) == llToLower(gMyName);
}

integer gForwardingStop = FALSE;

integer forward_stop_command()
{
    if (gForwardingStop)
    {
        return TRUE;
    }

    gForwardingStop = TRUE;
    llMessageLinked(LINK_SET, 0, "stop", NULL_KEY);
    return TRUE;
}

integer handle_command(string command)
{
    if (command == "start")
    {
        return TRUE;
    }

    if (command == "stop")
    {
        return forward_stop_command();
    }

    return FALSE;
}

integer handle_json(string message)
{
    string command = llToLower(llStringTrim(llJsonGetValue(message, ["COMMAND"]), STRING_TRIM));
    if (command == JSON_INVALID || command == "")
    {
        return FALSE;
    }

    string target = llJsonGetValue(message, ["NAME"]);
    if (!accepts_name(target))
    {
        return FALSE;
    }

    return handle_command(command);
}

integer handle_plain(string message)
{
    return handle_command(llToLower(llStringTrim(message, STRING_TRIM)));
}

integer process_message(string message)
{
    if (message == "")
    {
        return FALSE;
    }

    string trimmed = llStringTrim(message, STRING_TRIM);
    if (llGetSubString(trimmed, 0, 0) == "{")
    {
        return handle_json(trimmed);
    }
    return handle_plain(trimmed);
}

default
{
    state_entry()
    {
        gMyName = llGetObjectName();
        if (gChannel != 0)
        {
            start_listen();
        }
    }

    on_rez(integer start_param)
    {
        gChannel = start_param;
        start_listen();
    }

    listen(integer channel, string name, key id, string message)
    {
        process_message(message);
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (gForwardingStop && num == 0 && llToLower(str) == "stop")
        {
            gForwardingStop = FALSE;
            return;
        }

        if (num == 0)
        {
            process_message(str);
        }
        else if (num == 1)
        {
            process_message((string)id);
        }
    }
}
