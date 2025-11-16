// rez_attach.lsl  (Rezzer side)
// - Put this script in the AVSitter prim (same linkset as AVSitter).
// - Put all your attachment/prop objects in THIS prim's inventory (type: Object).
// - Each rezzed object should have its own script that listens on CMD_CHANNEL
//   and detaches/derezzes when it receives the "DETACH" message.

list gTeleporters;          // all object names from inventory
key  gSitter = NULL_KEY;    // current sitting avatar (from AVSitter 90060)
key  gCurrentRez = NULL_KEY;// last rezzed object key
float TIME_CHANGE = 15.0;   // seconds between object swaps (change as you want)

integer CMD_CHANNEL = -987654; // random negative channel for control
string  CMD_DETACH   = "DETACH";

// ---------------------- helpers ----------------------------

loadTeleporters()
{
    gTeleporters = [];
    integer count = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    for (i = 0; i < count; ++i)
    {
        string name = llGetInventoryName(INVENTORY_OBJECT, i);
        // Skip anything you don’t want here if needed
        gTeleporters += [ name ];
    }

    if (!llGetListLength(gTeleporters))
    {
        llOwnerSay("No OBJECTs found in inventory. Nothing to rez.");
    }
}

RezTP()
{
    integer len = llGetListLength(gTeleporters);
    if (!len)
    {
        llOwnerSay("RezTP(): gTeleporters is empty. Check inventory.");
        return;
    }

    // Ask previous object to detach/derez first
    if (gCurrentRez != NULL_KEY)
    {
        llRegionSayTo(gCurrentRez, CMD_CHANNEL, CMD_DETACH);
        // Let the object clean itself; we just forget its key here
        gCurrentRez = NULL_KEY;
    }

    // Pick random object name from list
    integer idx = (integer)llFrand((float)len);
    string objName = llList2String(gTeleporters, idx);

    // Rez near the furniture. Adjust offset if needed.
    vector rezPos = llGetPos() + <0.0, 0.0, 1.0>;
    rotation rezRot = llGetRot();

    // We pass CMD_CHANNEL as start_param so the rezzed object knows what to listen on
    llRezObject(objName, rezPos, ZERO_VECTOR, rezRot, CMD_CHANNEL);
}

// ---------------------- events -----------------------------

default
{
    state_entry()
    {
        loadTeleporters();
        llSetTimerEvent(0.0); // timer OFF by default
    }

    changed(integer change)
    {
        if (change & CHANGED_INVENTORY)
        {
            // reload list when inventory changes
            loadTeleporters();
        }
    }

    // AVSitter messages
    // 90060 = sit, 90065 = stand  (from AVSitter docs)
    link_message(integer sender, integer num, string msg, key id)
    {
        if (num == 90060) // sitter sits
        {
            // id = avatar UUID, msg = SITTER #
            gSitter = id;

            // First rez object
            RezTP();

            // Start timer for automatic swapping
            llSetTimerEvent(TIME_CHANGE);
        }
        else if (num == 90065) // sitter stands
        {
            // id = avatar who stood
            if (id == gSitter)
            {
                // Stop timer
                llSetTimerEvent(0.0);

                // Tell current object to detach/derez
                if (gCurrentRez != NULL_KEY)
                {
                    llRegionSayTo(gCurrentRez, CMD_CHANNEL, CMD_DETACH);
                    gCurrentRez = NULL_KEY;
                }

                gSitter = NULL_KEY;
            }
        }
    }

    // Called when this prim rezzes an object
    object_rez(key id)
    {
        // Remember latest rezzed object
        gCurrentRez = id;
    }

    timer()
    {
        // If no sitter, kill timer and do nothing
        if (gSitter == NULL_KEY)
        {
            llSetTimerEvent(0.0);
            return;
        }

        // Swap to a new random object
        RezTP();
    }
}
