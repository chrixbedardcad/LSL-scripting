integer CHANNEL_ID;
integer FLAG_ATTACH = FALSE;
default
{
    state_entry()
    {
        llOwnerSay("state_entry CHANNEL_ID: " + (string) CHANNEL_ID); 
    }
 
    on_rez(integer param)
    {
        CHANNEL_ID = param;
        llListen(CHANNEL_ID, "", NULL_KEY, "");
        llOwnerSay("on_rez param: " + (string) param);
    }
   
    experience_permissions(key agent)
    {
        llOwnerSay("Call Experience agent: " + (string) agent);
        if (FLAG_ATTACH) {
            llOwnerSay("Call Experience agent: " + (string) agent);
            llAttachToAvatarTemp(ATTACH_AVATAR_CENTER);
            FLAG_ATTACH = FALSE; 
        }
    } 

    listen( integer channel, string name, key id, string message )
    {
        string str;
        string channel_id;
        llOwnerSay("CHANNEL_ID : " + (string) CHANNEL_ID+ " listen Channel: " + (string) channel +" name: " +name+  " message: "  + message + " key:" + (string) id + " llGetOwner(): " + (string) llGetOwner());
     
        if ((str = llJsonGetValue(message, ["AVI_UUID"])) != JSON_INVALID){
                FLAG_ATTACH = TRUE;
                llRequestExperiencePermissions((key) str, "");
            } 
        
        if ((str = llJsonGetValue(message, ["DETACH"])) != JSON_INVALID){
            llDetachFromAvatar();
            llDie();
        }
            
    }
}