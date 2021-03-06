global function Cl_CustomTDM_Init

global function ServerCallback_TDM_DoAnnouncement
global function ServerCallback_TDM_SetSelectedLocation
global function ServerCallback_TDM_DoLocationIntroCutscene
global function ServerCallback_TDM_PlayerKilled
//ServerCallback_PointCreatedglobal function ServerCallback_PointCreated

global function Cl_RegisterLocation

struct {

    LocationSettings &selectedLocation
    array choices
    array<LocationSettings> locationSettings
    var scoreRui
} file;


struct PlayerInfo 
{
    string name
    int team
    int score
}


void function Cl_CustomTDM_Init()
{
    print("Cl_CustomTDM_Init")
    AddCreateCallback("prop_dynamic", propDynamicCreated)
    //Add
}

void function Cl_RegisterLocation(LocationSettings locationSettings)
{
    file.locationSettings.append(locationSettings)
}


void function MakeScoreRUI()
{
    if ( file.scoreRui != null)
    {
        RuiSetString( file.scoreRui, "messageText", "0%  |  0%" )
        return
    }
    clGlobal.levelEnt.EndSignal( "CloseScoreRUI" )

    UISize screenSize = GetScreenSize()
    var screenAlignmentTopo = RuiTopology_CreatePlane( <( screenSize.width *-0.078),( screenSize.height * -0.385 ), 0>, <float( screenSize.width ), 0, 0>, <0, float( screenSize.height ), 0>, false )
    var rui = RuiCreate( $"ui/announcement_quick_right.rpak", screenAlignmentTopo, RUI_DRAW_HUD, RUI_SORT_SCREENFADE + 1 )
    
    RuiSetGameTime( rui, "startTime", Time() )
    RuiSetString( rui, "messageText", "0%  |  0%" )
    RuiSetString( rui, "messageSubText", "Text 2")
    RuiSetFloat( rui, "duration", 9999999 )
    RuiSetFloat3( rui, "eventColor", SrgbToLinear( <128, 188, 255> ) )
    
    file.scoreRui = rui
    
    OnThreadEnd(
        function() : ( rui )
        {
            RuiDestroy( rui )
            file.scoreRui = null
        }
    )
    
    WaitForever()
}










void function ServerCallback_TDM_DoAnnouncement(float duration, int type)
{
    string message = ""
    string subtext = ""
    switch(type)
    {

        case eTDMAnnounce.ROUND_START:
        {
            thread MakeScoreRUI();
            //thread Point_CreateHUDMarker();
            message = ""
            subtext = ""
            break
        }
        case eTDMAnnounce.VOTING_PHASE:
        {
            clGlobal.levelEnt.Signal( "CloseScoreRUI" )
            message = "Pre-game"
            subtext = "@d0dgerz King of the Hill"
            break
        }
        case eTDMAnnounce.MAP_FLYOVER:
        {
            
            if(file.locationSettings.len())
                message = file.selectedLocation.name
            break
        }
    }
	AnnouncementData announcement = Announcement_Create( message )
    Announcement_SetSubText(announcement, subtext)
	Announcement_SetStyle( announcement, ANNOUNCEMENT_STYLE_CIRCLE_WARNING )
	Announcement_SetPurge( announcement, true )
	Announcement_SetOptionalTextArgsArray( announcement, [ "true" ] )
	Announcement_SetPriority( announcement, 200 ) //Be higher priority than Titanfall ready indicator etc
	announcement.duration = duration
	AnnouncementFromClass( GetLocalViewPlayer(), announcement )
}




void function ServerCallback_TDM_DoLocationIntroCutscene()
{
    thread ServerCallback_TDM_DoLocationIntroCutscene_Body()
}

void function ServerCallback_TDM_DoLocationIntroCutscene_Body()
{
    float desiredSpawnSpeed = Deathmatch_GetIntroSpawnSpeed()
    float desiredSpawnDuration = Deathmatch_GetIntroCutsceneSpawnDuration()
    float desireNoSpawns = Deathmatch_GetIntroCutsceneNumSpawns()
    

    entity player = GetLocalClientPlayer()
    
    if(!IsValid(player)) return
    

    EmitSoundOnEntity( player, "music_skyway_04_smartpistolrun" )
     
    float playerFOV = player.GetFOV()
    
    entity camera = CreateClientSidePointCamera(file.selectedLocation.spawns[0].origin + file.selectedLocation.cinematicCameraOffset, <90, 90, 0>, 17)
    camera.SetFOV(90)

    entity cutsceneMover = CreateClientsideScriptMover($"mdl/dev/empty_model.rmdl", file.selectedLocation.spawns[0].origin + file.selectedLocation.cinematicCameraOffset, <90, 90, 0>)
    camera.SetParent(cutsceneMover)
	GetLocalClientPlayer().SetMenuCameraEntity( camera )

    ////////////////////////////////////////////////////////////////////////////////
    ///////// EFFECTIVE CUTSCENE CODE START


    array<LocPair> cutsceneSpawns
    for(int i = 0; i < desireNoSpawns; i++)
    {
        if(!cutsceneSpawns.len())
            cutsceneSpawns = clone file.selectedLocation.spawns

        LocPair spawn = cutsceneSpawns.getrandom()
        cutsceneSpawns.fastremovebyvalue(spawn)

        cutsceneMover.SetOrigin(spawn.origin)
        camera.SetAngles(spawn.angles)



        cutsceneMover.NonPhysicsMoveTo(spawn.origin + AnglesToForward(spawn.angles) * desiredSpawnDuration * desiredSpawnSpeed, desiredSpawnDuration, 0, 0)
        wait desiredSpawnDuration
    }

    ///////// EFFECTIVE CUTSCENE CODE END
    ////////////////////////////////////////////////////////////////////////////////

    GetLocalClientPlayer().ClearMenuCameraEntity()
    cutsceneMover.Destroy()

    if(IsValid(player))
    {
        FadeOutSoundOnEntity( player, "music_skyway_04_smartpistolrun", 1 )
    }
    if(IsValid(camera))
    {
        camera.Destroy()
    }
    
    
}



void function ServerCallback_TDM_SetSelectedLocation(int sel)
{
    file.selectedLocation = file.locationSettings[sel]
}

void function ServerCallback_TDM_PlayerKilled() //rename???
{
    if(file.scoreRui)
        RuiSetString( file.scoreRui, "messageText",GameRules_GetTeamScore(TEAM_IMC) + "%  |  " + GameRules_GetTeamScore(TEAM_MILITIA) + "%" );
}



void function propDynamicCreated( entity ent )
{
  if ( ent.GetScriptName() != "controlPoint" ) return


    //circle.EndSignal( "OnDestroy" )

    //var rui = AddOverheadIcon( ent, RESPAWN_BEACON_ICON, false, $"ui/overhead_icon_respawn_beacon.rpak" )
    //var rui = AddOverheadIcon( ent, RESPAWN_BEACON_ICON, false, $"ui/overhead_icon_respawn_beacon.rpak" )


    entity localViewPlayer = GetLocalViewPlayer()
    vector pos = ent.GetOrigin() + ( ent.GetUpVector() * 1 )
    var rui = CreateCockpitRui( $"ui/dirty_bomb_marker_icons.rpak", RuiCalculateDistanceSortKey( localViewPlayer.EyePosition(), pos ) )
    RuiSetGameTime( rui, "startTime", Time() )
    RuiTrackFloat3( rui, "pos", ent, RUI_TRACK_OVERHEAD_FOLLOW )
    RuiKeepSortKeyUpdated( rui, true, "pos" )

    asset icon = $"rui/hud/ultimate_icons/ultimate_wattson_in_world"

    RuiSetImage( rui, "bombImage", icon )
    RuiSetImage( rui, "triggeredImage", icon )









    /*RuiSetFloat2( rui, "iconSize", <60,60,0> )
    RuiSetFloat( rui, "distanceFade", 50000 )
    RuiSetBool( rui, "adsFade", true )
    RuiSetString( rui, "hint", "Point" )*/


    /*
    var ruix = CreateCockpitRui(    , HUD_Z_BASE )
    RuiSetBool( ruix, "isVisible", true )
    //RuiSetImage( ruix, "", icon )
    RuiSetGameTime( ruix, "startTime", Time() )
    RuiSetGameTime( ruix, "endTime", Time() + 5 )
    RuiSetString( ruix, "hintKeyboardMouse", "Capturing point" )
    print("abc")*/


    /*UISize screenSize = GetScreenSize()
    var screenAlignmentTopo = RuiTopology_CreatePlane( <(screenSize.width * -0.3),( screenSize.height * -0.52 ), 0>, <float( screenSize.width ), 0, 0>, <0, float( screenSize.height ), 0>, false )
    var ruix = RuiCreate( $"ui/announcement_quick_right.rpak", screenAlignmentTopo, RUI_DRAW_HUD, RUI_SORT_SCREENFADE + 1 )
    
    RuiSetGameTime( ruix, "startTime", Time() )
    RuiSetString( ruix, "messageText", "Contested!" )
    RuiSetString( ruix, "messageSubText", "")
    RuiSetFloat( ruix, "duration", 9999999 )
    RuiSetFloat3( ruix, "eventColor", SrgbToLinear( <255, 255, 0> ) )*/



    //WaitForever()

    
}





var function CreateTemporarySpawnRUI(entity parentEnt, float duration)
{
    var rui = AddOverheadIcon( parentEnt, RESPAWN_BEACON_ICON, false, $"ui/overhead_icon_respawn_beacon.rpak" )
	RuiSetFloat2( rui, "iconSize", <80,80,0> )
	RuiSetFloat( rui, "distanceFade", 50000 )
	RuiSetBool( rui, "adsFade", true )
	RuiSetString( rui, "hint", "SPAWN POINT" )

    wait duration

    parentEnt.Destroy()
}



