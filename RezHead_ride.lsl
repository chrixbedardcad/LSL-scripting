// rez_random_and_link_on_rez_min_dialog.lsl
// Rezzes & links a random inventory object when THIS object is rezzed.
// Only asks for PERMISSION_CHANGE_LINKS when truly needed.

vector   REZ_OFFSET        = <0.0, 0.0, 1.0>;
rotation REZ_ROTATION      = <0.0, 0.0, 0.0, 1.0>;
float    REZ_TO_LINK_DELAY = 0.25;

key     gPendingChild = NULL_KEY;
integer gHasPerm      = FALSE;
integer gAutoOnRez    = FALSE;

// Pick a random object from inventory
string pick_random_object()
{
    integer count = llGetInventoryNumber(INVENTORY_OBJECT);
    if (count <= 0) return "";

    list objs = [];
    integer i;
    for (i = 0; i < count; i++)
    {
        objs += [ llGetInventoryName(INVENTORY_OBJECT, i) ];
    }

    integer n = llGetListLength(objs);
    if (n == 0) return "";

    integer idx = (integer)llFrand((float)n);
    return llList2String(objs, idx);
}

integer doRezRandom()
{
    string item = pick_random_object();
    if (item == "")
    {
        llOwnerSay("No OBJECTs in inventory to rez.");
        return FALSE;
    }

    vector   rezPos = llGetPos() + (REZ_OFFSET * llGetRot());
    rotation rezRot = llGetRot() * REZ_ROTATION;

    llRezObject(item, rezPos, ZERO_VECTOR, ZERO_ROTATION, 0);
    return TRUE;
}

default
{
    state_entry()
    {
        // Don’t request perms here; wait until we actually need them.
    }

    on_rez(integer start_param)
    {
        // Mark that after we get perms, we should auto-rez one child
        gAutoOnRez = TRUE;

        if (!gHasPerm)
        {
            llRequestPermissions(llGetOwner(), PERMISSION_CHANGE_LINKS);
        }
        else
        {
            // Already have perms, just do it
            doRezRandom();
        }
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_CHANGE_LINKS)
        {
            gHasPerm = TRUE;

            if (gAutoOnRez)
            {
                gAutoOnRez = FALSE;
                doRezRandom();
            }
        }
        else
        {
            gHasPerm = FALSE;
            llOwnerSay("Need permission to change links.");
        }
    }

    object_rez(key child_id)
    {
        gPendingChild = child_id;
        llSetTimerEvent(REZ_TO_LINK_DELAY);
    }

    timer()
    {
        llSetTimerEvent(0.0);

        if (!gHasPerm || gPendingChild == NULL_KEY) return;

        llCreateLink(gPendingChild, TRUE); // rezzer stays root
        gPendingChild = NULL_KEY;
    }
}
