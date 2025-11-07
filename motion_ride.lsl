// Global variables
integer CHANNEL_ID =  -777;
integer CHANNEL_REZZER = -339189999;
integer toggle = TRUE; //debug
vector START_POS;
rotation START_ROT;
integer notecardLine = 0;
list gKeyframeList = [];
integer file_id;
string file_name;
integer file_line_number;
key file_request;
key UUID_AVATAR_0 = NULL_KEY;
key UUID_AVATAR_1 = NULL_KEY;
integer FLAG_SIT = FALSE;
string REF_POSE_NAME;
integer FLAG_FLY = FALSE;
integer FLAG_WAIT_FOR_PARTNERS = FALSE;
integer FLAG_MOTION_ON = FALSE;
integer FLAG_PLAY = FALSE;
rotation NormalizeRotation(rotation Q)
{
    float MagQ = llSqrt(Q.x*Q.x + Q.y*Q.y +Q.z*Q.z + Q.s*Q.s);
    return <Q.x/MagQ, Q.y/MagQ, Q.z/MagQ, Q.s/MagQ>;
}

SetLinkText(integer link, string text, vector color, float alpha)
{
    llSetLinkPrimitiveParamsFast(link,
        [PRIM_TEXT, text, color, alpha]);
}

Play(key avatar ) {
//    return;
   if (FLAG_PLAY) return;
   FLAG_PLAY = TRUE;
    llRegionSay(CHANNEL_REZZER, "NEW");
    llSetLinkAlpha(6, 0.0, ALL_SIDES);
    llSetLinkAlpha(6, 0.0, ALL_SIDES);
    llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_TEXT, "", <0,0,0>, 0]);
    llSetKeyframedMotion([],[]);
    rotation TargetRot;
    TargetRot  = NormalizeRotation (llGetRot()/START_ROT);  
    //TargetRot  = NormalizeRotation (START_ROT);  
    llRequestPermissions(avatar, PERMISSION_CONTROL_CAMERA);
    llSetTimerEvent(309.18);
   
    
}
Stop(){
    llSetKeyframedMotion([], []);
    llSetRot(START_ROT);
    llSetRegionPos(START_POS);
    FLAG_MOTION_ON = FALSE;
    llSetAlpha( 1, ALL_SIDES);

}

// Function to parse each line of the notecard
vector parseStartPos(string line){
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    vector pos = (vector)llGetSubString(line, startIndex, endIndex);
    return pos;
}

rotation parseStartRot(string line){
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    line = llDeleteSubString(line, 0, endIndex);
    startIndex = llSubStringIndex(line, "<");
    endIndex = llSubStringIndex(line, ">");
    rotation rot = (rotation)llGetSubString(line, startIndex, endIndex);
    return rot;
}
list parseLine(string line) {
    // Remove comments and square brackets, then extract the relevant data
    integer startIndex = llSubStringIndex(line, "<");
    integer endIndex = llSubStringIndex(line, ">");
    vector pos = (vector)llGetSubString(line, startIndex, endIndex);
    
    line = llDeleteSubString(line, 0, endIndex);
    startIndex = llSubStringIndex(line, "<");
    endIndex = llSubStringIndex(line, ">");
    rotation rot = (rotation)llGetSubString(line, startIndex, endIndex);
    
    float time = (float)llDeleteSubString(line, 0, endIndex);
    
   // llOwnerSay( "DEBUG ::: pos: " + (string) pos + " rot: " + (string) rot + " time: " + (string) time);
    // Return as a list
    return [pos, rot, time];
}

// Function to dump the content of the keyframe list for debugging
dumpKeyframeList() {
    integer i;
    integer len = llGetListLength(gKeyframeList);
    for (i = 0; i < len; i += 3) {
        vector pos = llList2Vector(gKeyframeList, i);
        rotation rot = llList2Rot(gKeyframeList, i + 1);
        float time = llList2Float(gKeyframeList, i + 2);
        
        llOwnerSay("Position(" + (string) (i/3) + "): " + (string)pos);
        llOwnerSay("Rotation: " + (string)rot);
        llOwnerSay("Time: " + (string)time);
    }
}

StartReadingNoteCard() {
        llSetKeyframedMotion([],[]);  
        float time = llGetAndResetTime();
    //    llOwnerSay("Building Path... "  + (string) time + " sec.");
        //notecardQueryId = llGetNotecardLine(notecardNameOrKey, notecardLine);
        file_id =0; 
        file_name = llGetInventoryName(INVENTORY_NOTECARD, file_id); // get the name of the first notecard in the object's inventory
        file_line_number = 0;
        file_request = llGetNotecardLine(file_name, file_line_number);
}

// Event that handles notecard data retrieval
default {
    state_entry() {
  //      llSetAlpha( 0, ALL_SIDES);
        llListen(CHANNEL_ID, "", NULL_KEY, "");
        llSitTarget(<0.0, 0.0, 1.0>, ZERO_ROTATION);        
        llSetKeyframedMotion([],[]); 
        llSetLinkPrimitiveParamsFast(LINK_ROOT, [
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_CONVEX,
            PRIM_LINK_TARGET, LINK_ALL_CHILDREN,
            PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE
        ]);
        llSetText("Fly Duo", <1,1,1>, 1);        
        StartReadingNoteCard();

    }
    
    on_rez(integer start_param)
    {
        // Restarts the script every time the object is rezzed
   //     llResetScript(); 
    }
    run_time_permissions(integer perm)
    {
        // Check if we have been granted camera control permissions
        if (perm & PERMISSION_CONTROL_CAMERA)
        {
            // Configure the camera parameters to stay behind the avatar
            list camera_params = [
                CAMERA_ACTIVE, TRUE,                   // Activate custom camera control
                CAMERA_BEHINDNESS_ANGLE, PI,           // Set camera directly behind the avatar
                CAMERA_BEHINDNESS_LAG, 0.1,            // Slight lag to allow smooth camera movement
                CAMERA_DISTANCE, 3.0,                  // Distance from avatar to camera
                CAMERA_FOCUS_LAG, 0.0,                 // No lag for focus
                CAMERA_FOCUS_OFFSET, <0.0, 0.0, 1.0>   // Offset focus above the avatar's head
            ];

            llSetCameraParams(camera_params);
            if (FLAG_WAIT_FOR_PARTNERS) 
                return;
            else {
                llSetKeyframedMotion([], []);
                llSetRegionPos(START_POS);
                llSleep(0.5); 
                llSetRot(START_ROT);
                llSleep(0.5); 
                FLAG_MOTION_ON = TRUE ;
                llSetKeyframedMotion(gKeyframeList, [KFM_MODE,KFM_LOOP]); 
                }
        }
    } 
    
    changed(integer change)
    {
        // note that it's & and not &&... it's bitwise!
        if (change & CHANGED_INVENTORY)         
        {
            llResetScript();
        }

        if (change & CHANGED_LINK)
        { 
   //       llOwnerSay("Change Links: " + (string) llAvatarOnSitTarget()); 
        /*    key av = llAvatarOnSitTarget();
            if (av) // evaluated as true if key is valid and not NULL_KEY
            {
                Play(av);
            } else
                Stop(); */
        }
    } 
    
    dataserver(key query_id, string data) {
       if (query_id == file_request) {
            while (data != EOF && data != NAK) {
                data = llGetNotecardLineSync(file_name, file_line_number);
                if (file_line_number == 0){
                    START_ROT = parseStartRot(data);                    
                    START_POS = parseStartPos(data);
                //    llOwnerSay("Set Start position: "  +  (string) START_POS);
                } else if (data == NAK){
                    llOwnerSay("Warning: NAK reading file: " + file_name + " line: " + (string) file_line_number);
                    file_request = llGetNotecardLine(file_name, file_line_number);
                } else if (data != EOF) {
              //      llOwnerSay("Processing " + file_name + " done " + (string) file_line_number + " line");
                    gKeyframeList += parseLine(data);
                } else {
                    float time = llGetTime();
                    llOwnerSay("Reading " + file_name + " done " + (string) file_line_number + " lines. " + (string) time + " sec.");
                //    dumpKeyframeList();
                    return;
                }
                file_line_number++;
            } 
        } 
    }

 listen(integer channel, string name, key id, string message)
    {
   //    llOwnerSay("channel: "+ (string) channel + " name: " + name + " id: " + (string) id + "  message: " +message); 
       string str;
       if ((str = llJsonGetValue(message, ["END_PATH"])) != JSON_INVALID)
        {
        //   llOwnerSay("END_PATH Detected");
            Stop();
        }
    }
    
timer()
{
   llOwnerSay("Force a reset: START_ROT: " + (string) START_ROT + " START_POS: " + (string) START_POS);    
     llSetKeyframedMotion([], []);
    llSetRegionPos(START_POS);
    llSleep(0.5); 
    llSetRot(START_ROT);
    llSleep(0.5); 
    llSetKeyframedMotion(gKeyframeList, [KFM_MODE,KFM_LOOP]); 
}


   link_message(integer sender_num, integer num, string msg, key id)
    {
   //     llOwnerSay("RezzerSitInterface - Script - sender_num: " + (string) sender_num + " num: " + (string) num + " msg: " + msg + " id: " + (string) id);
   //     llOwnerSay("CHANNEL_CAROUSEL_ATTACH: " + (string) CHANNEL_CAROUSEL_ATTACH);
        // Get Pos Update
        if(num==90045) {
           
            // The avatar UUID
            key AVATAR_UUID = id;
           
            // Extract the data into a list
            list data = llParseStringKeepNulls(msg,["|"],[]);
           
            // The SITTER# the pose is playing for
            integer SITTER_NUMBER = (integer)llList2String(data,0);
           
            // The name of the pose
            REF_POSE_NAME = llList2String(data,1);
           
            // The animation file
            string ANIM_FILE = llList2String(data,2);
           
            // The SET#
            integer SET = (integer)llList2String(data,3);
           
            // A list of UUIDs of all sitting avatars separated by the ( @ ) character
            list ALL_SITTERS = llParseStringKeepNulls(llList2String(data,4),["@"],[]);
           
            // The name the SYNC pose the avatar is leaving
            string OLD_SYNC_NAME = llList2String(data,5);
           
            // TRUE if the pose is a SYNC pose
            integer IS_SYNC = (integer)llList2String(data,6);
            if (FLAG_MOTION_ON){
      //          llOwnerSay("KFM_CMD_PLAY from 90045 link message");
           //     llSetKeyframedMotion([],[KFM_COMMAND, KFM_CMD_PAUSE]);
            //    llSleep(0.2);
            //    llSetKeyframedMotion([],[KFM_COMMAND, KFM_CMD_PLAY]);
            }

        }

        // Stand Up AVSitter
        if(num == 90065)
        {
  //          llOwnerSay("Avatar #" + msg + " " + llKey2Name(id) + " is Stand Up");
            if ((integer) msg ==0){
                UUID_AVATAR_0 = NULL_KEY;
                if (!FLAG_FLY) 
                    llSetText("Fly Duo", <1,1,1>, 1);
            }
            if ((integer) msg ==1) {
                UUID_AVATAR_1 = NULL_KEY;
                if (!FLAG_FLY)
                    llSetText("Waiting for a Flight Partner...", <1,1,1>, 1);
            }
            
            if ((UUID_AVATAR_0 == NULL_KEY) && (UUID_AVATAR_1 == NULL_KEY))
                if (FLAG_SIT)
                    FLAG_SIT = FALSE;
                else {
                    llSleep(1); 
                    llDie();  
                }
        }
        
        // Sit AVSitter
        if(num == 90060)
        {
            if ((integer) msg ==0){
                UUID_AVATAR_0 = id;
                FLAG_SIT = TRUE;
                llSetText("Waiting for a Flight Partner...", <1,1,1>, 1);
                llRequestPermissions(UUID_AVATAR_0, PERMISSION_CONTROL_CAMERA);
                FLAG_WAIT_FOR_PARTNERS = TRUE;
            }
            if ((integer) msg ==1) {
                UUID_AVATAR_1 = id;
                FLAG_SIT = FALSE;
                FLAG_FLY = TRUE;
                FLAG_WAIT_FOR_PARTNERS = FALSE;
                Play(id);
            }
      }
    }
    
}
