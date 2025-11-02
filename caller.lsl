// caller.lsl -- Reads rez.cfg and sends rez commands to rezzer via llRegionSay
// Assumes rez.cfg is a notecard or script file in the object's inventory with
// one JSON object per line describing the object name and quantity.

integer CHANNEL = -987654;          // Channel used to communicate with rezzer.lsl
string  CONFIG_NOTECARD = "rez.cfg"; // Name of the configuration notecard/file

// llGetNotecardLineSync returns literal strings when encountering specific conditions.
// Define them explicitly so the compiler recognizes the names.
string  NOTE_EOF        = EOF;          // End-of-file marker
string  NOTE_NOT_FOUND  = "NOT_FOUND"; // Notecard missing from inventory
string  NOTE_NOT_READY  = "NOT_READY"; // Asset data not yet available
string  NOTE_NAK        = NAK;           // Dataserver indicates to retry asynchronously

list gEntries;          // Stores each configuration line as a JSON string
integer gReady = FALSE; // TRUE when configuration is fully loaded
string  gPayloadTemplate;
integer gLoadLine;      // Current line number requested from the notecard
key     gLoadRequest;   // Handle for the outstanding notecard request
integer gLoading;       // TRUE while a notecard request is pending

string build_payload_template()
{
    return llList2Json(JSON_OBJECT, [
        "COMMAND",    "rez",
        "OBJECT_NAME", "",
        "QTY",         "0"
    ]);
}

// --- Helpers ----------------------------------------------------------------

integer entry_count()
{
    return llGetListLength(gEntries);
}

integer start_config_load()
{
    gEntries = [];
    gReady = FALSE;
    gLoading = FALSE;
    gLoadLine = 0;
    gLoadRequest = NULL_KEY;

    if (gPayloadTemplate == "")
    {
        gPayloadTemplate = build_payload_template();
    }

    if (llGetInventoryType(CONFIG_NOTECARD) != INVENTORY_NOTECARD)
    {
        llOwnerSay("caller.lsl: Unable to find configuration notecard '" + CONFIG_NOTECARD + "'.");
        return FALSE;
    }
    gLoadLine = 0;
    gLoadRequest = llGetNotecardLine(CONFIG_NOTECARD, gLoadLine);

    if (gLoadRequest == NULL_KEY)
    {
        llOwnerSay("caller.lsl: Failed to request configuration notecard '" + CONFIG_NOTECARD + "'.");
        return FALSE;
    }

    gLoading = TRUE;
    return TRUE;
}

integer parse_quantity(string json)
{
    string qtyStr = llJsonGetValue(json, ["QTY"]);
    if (qtyStr == JSON_INVALID) return 0;
    return (integer)qtyStr;
}

string parse_object_name(string json)
{
    return llJsonGetValue(json, ["Object_Name"]);
}

integer send_cmd(integer channelId, string object_name, integer qty)
{
    string payload = gPayloadTemplate;
    payload = llJsonSetValue(payload, ["OBJECT_NAME"], object_name);
    payload = llJsonSetValue(payload, ["QTY"], (string) qty);

    llRegionSay(channelId, payload);
    return TRUE;
}

integer send_stop_command()
{
    string payload = llList2Json(JSON_OBJECT, [
        "COMMAND", "stop"
    ]);

    llRegionSay(CHANNEL, payload);
    return TRUE;
}

integer send_random_command()
{
    integer count = entry_count();
    if (!gReady || count <= 0) return FALSE;

    send_stop_command();

    integer index = (integer)llFrand((float)count);
    string jsonLine = llList2String(gEntries, index);

    string objName = parse_object_name(jsonLine);
    integer qty    = parse_quantity(jsonLine);

    if (objName == JSON_INVALID || objName == "")
    {
        llOwnerSay("caller.lsl: Invalid Object_Name in configuration entry #" + (string)(index + 1));
        return FALSE;
    }

    if (qty <= 0)
    {
        qty = 1; // fallback to one rez if missing/invalid
    }

    return send_cmd(CHANNEL, objName, qty);
}

// --- Events -----------------------------------------------------------------

default
{
    state_entry()
    {
        start_config_load();
    }

    on_rez(integer param)
    {
        start_config_load();
    }

    touch_start(integer total_number)
    {
        if (!gReady)
        {
            llOwnerSay("caller.lsl: Configuration not ready yet.");
            return;
        }

        if (!send_random_command())
        {
            llOwnerSay("caller.lsl: Failed to send rez request.");
        }
    }

    changed(integer change)
    {
        if (change & (CHANGED_INVENTORY | CHANGED_OWNER))
        {
            start_config_load();
        }
    }

    dataserver(key request_id, string data)
    {
        if (!gLoading || request_id != gLoadRequest)
        {
            return;
        }

        string message = data;

        while (message != NOTE_EOF && message != NOTE_NAK && message != NOTE_NOT_FOUND && message != NOTE_NOT_READY)
        {
            string trimmed = llStringTrim(message, STRING_TRIM);
            if (trimmed != "")
            {
                gEntries += [trimmed];
            }

            ++gLoadLine;
            message = llGetNotecardLineSync(CONFIG_NOTECARD, gLoadLine);
        }

        if (message == NOTE_NAK || message == NOTE_NOT_READY)
        {
            gLoadRequest = llGetNotecardLine(CONFIG_NOTECARD, gLoadLine);
            return;
        }

        gLoading = FALSE;

        if (message == NOTE_EOF)
        {
            gReady = TRUE;
            llOwnerSay("caller.lsl: Loaded " + (string)entry_count() + " configuration entries.");
            return;
        }

        if (message == NOTE_NOT_FOUND)
        {
            llOwnerSay("caller.lsl: Unable to read configuration notecard '" + CONFIG_NOTECARD + "'.");
            return;
        }

        llOwnerSay("caller.lsl: Unexpected response while reading configuration notecard.");
    }
}
