//integer CHANNEL = -55677;
integer CHANNEL = -339189999;
string POSE_BALL;
rotation START_ROT;
default
{
    state_entry()
    {
        llListen(CHANNEL, "", "", "");
        POSE_BALL = llGetInventoryName(INVENTORY_OBJECT, 0);
         rotation TargetRot;
        START_ROT = llEuler2Rot(<0, 0.0, 0>);
    }

    touch_start(integer total_number)
    {
        if ((llDetectedKey(0) == llGetOwner()) || (llDetectedKey(0) == "95288d5b-14e2-4d4a-9332-2e5ed9247455"))
            llRezObject(POSE_BALL, llGetPos() + <0.0,0.0,.5>, <0.0,0.0,0.0>, START_ROT, 0);
    }
    
     listen(integer channel, string name, key id, string message)
    {
       // llOwnerSay("Call message to rez: " + message);
        if (message == "NEW");
            llRezObject(POSE_BALL, llGetPos() + <0.0,0.0,.5>, <0.0,0.0,0.0>, START_ROT, 0);
    }
    
    on_rez(integer start_param)
    {
        llResetScript();
    }
}
