global function _CustomTDM_Init
global function _RegisterLocation
table playersInfo



global table<entity,bool> readyList = {}
global array<entity> respawnQueue = []
global int choice = 6 //Default map pick = Ambush

struct PlayerInfo 
{
    string name
    int team
    int score
    int deaths
    float kd
    int damage
    int lastLatency
}

enum eTDMState
{
	IN_PROGRESS = 0
	WINNER_DECIDED = 1
}

struct {
    int tdmState = eTDMState.IN_PROGRESS
    array<entity> playerSpawnedProps
    LocationSettings& selectedLocation
    array<LocationSettings> locationSettings
    array<ItemFlavor> characters
    array<string> whitelistedWeapons
    int Picked = 8
    entity bubbleBoundary
    entity previousChampion
    entity previousChallenger
    int deathPlayersCounter=0
    int maxPlayers
    int maxTeams
} file;

/*   _____          __  __ ______   _      ____   ____  _____  
  / ____|   /\   |  \/  |  ____| | |    / __ \ / __ \|  __ \ 
 | |  __   /  \  | \  / | |__    | |   | |  | | |  | | |__) |
 | | |_ | / /\ \ | |\/| |  __|   | |   | |  | | |  | |  ___/ 
 | |__| |/ ____ \| |  | | |____  | |___| |__| | |__| | |     
  \_____/_/    \_\_|  |_|______| |______\____/ \____/|_|     
                                                             
                                                             */

void function _CustomTDM_Init()
{
    AddCallback_OnClientConnected( void function(entity player) { thread _OnPlayerConnected(player) } )
    AddCallback_OnPlayerKilled(void function(entity victim, entity attacker, var damageInfo) {thread _OnPlayerDied(victim, attacker, damageInfo)})
    

    AddClientCommandCallback("end_game", ClientCommand_EndGame)
    AddClientCommandCallback("ready", ClientCommand_Ready)
    AddClientCommandCallback("change_team", ClientCommand_ChangeTeam)
    AddClientCommandCallback("select_map",ClientCommand_SelectMap)
    AddClientCommandCallback("spawn_deathbox",ClientCommand_SpawnDeathbox)
    AddClientCommandCallback("destroy_doors",ClientCommand_DestroyDoors)
    AddClientCommandCallback("scoreboard", ClientCommand_Scoreboard)
    AddClientCommandCallback("latency", ClientCommand_ShowLatency)


    thread RunTDM()

    // Whitelisted weapons
    for(int i = 0; GetCurrentPlaylistVarString("whitelisted_weapon_" + i.tostring(), "~~none~~") != "~~none~~"; i++)
    {
        file.whitelistedWeapons.append(GetCurrentPlaylistVarString("whitelisted_weapon_" + i.tostring(), "~~none~~"))
    }

}

void function _RegisterLocation(LocationSettings locationSettings)
{
    file.locationSettings.append(locationSettings)

}

LocPair function _GetVotingLocation()
{
    switch(GetMapName())
    {
        case "mp_rr_canyonlands_staging":
            return NewLocPair(<26794, -6241, -27479>, <0, 0, 0>)
        case "mp_rr_canyonlands_64k_x_64k":
        case "mp_rr_canyonlands_mu1":
        case "mp_rr_canyonlands_mu1_night":
            return NewLocPair(<-6252, -16500, 3296>, <0, 0, 0>)
        case "mp_rr_desertlands_64k_x_64k":
        case "mp_rr_desertlands_64k_x_64k_nx":
                return NewLocPair(<1763, 5463, -3145>, <5, -95, 0>)
        default:
            Assert(false, "No voting location for the map!")
    }
    unreachable
}


void function RunTDM()
{
    WaitForGameState(eGameState.Playing)
    for(; ; )
    {
        VotingPhase();
        StartRound();
    }
    WaitForever()
}

void function VotingPhase()
{
    {
        //Reset ready statuses
        foreach(player in readyList)
        {
            readyList.player = false
        }
        DestroyPlayerProps();
        SetGameState(eGameState.MapVoting)

        //Reset scores 
        GameRules_SetTeamScore(TEAM_IMC, 0)
        GameRules_SetTeamScore(TEAM_MILITIA, 0)
        

        foreach(player in GetPlayerArray()) 
        {
            if(!IsValid(player)) continue;
            _HandleRespawn(player)
            MakeInvincible(player)
    		HolsterAndDisableWeapons( player )
            Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 3, eTDMAnnounce.VOTING_PHASE)
            TpPlayerToSpawnPoint(player)
            player.UnfreezeControlsOnServer();      
        }
        wait 4
        foreach(player in GetPlayerArray())
        {
            thread Message(player, "Pre-game", helpMessage(), 15)
        }



         //Maybe working
        while(GetGameState() == eGameState.MapVoting)
        {
            int ready_count = 0
            foreach(item in readyList)
            {
                if(item == true) ready_count ++

            }
            wait 1     
            if(ready_count >= GetPlayerArray().len())
            {
                break
            }
        }
        file.selectedLocation = file.locationSettings[choice]
        thread SpawnWave()
        StartRound()
    }
}   

void function StartRound() 
{
    SetGameState(eGameState.Playing)
    int countdown = 5
    foreach(player in GetPlayerArray())
    {   
        print("\n\n\n\n" + IsValid(player))
        if( IsValid( player ) )
        {
            Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 0, eTDMAnnounce.ROUND_START)
            player.FreezeControlsOnServer()
            ScreenFadeFromBlack(player, 0.5, 0.5)
            TpPlayerToSpawnPoint(player)
        }
    }    
    while (countdown > 3)
    { 
        foreach (player in GetPlayerArray())
        {
            Message(player,"Starting in " + countdown,"", 2,"")
        }
        wait 1
        countdown--
    }
    while (countdown <= 3 && countdown != 1)
    {
        foreach(player in GetPlayerArray())
        {
        Message(player,"Starting in " + countdown,"", 2,"UI_Survival_Intro_LaunchCountDown_3Seconds")
        }
        wait 1
        countdown--
    }
    foreach(player in GetPlayerArray())
    {
    Message(player,"Starting in " + countdown,"", 1,"UI_Survival_Intro_LaunchCountDown_3Seconds")
    }
    wait 1

    foreach(player in GetPlayerArray())
    {
    thread EmitSoundOnEntityOnlyToPlayer(player,player,"UI_Survival_Intro_LaunchCountDown_Finish")

    ClearInvincible(player)
    DeployAndEnableWeapons(player)
    player.UnforceStand()  
    player.UnfreezeControlsOnServer()
    }           

    AddSpawnCallback("prop_dynamic", _OnPropDynamicSpawned)
    ControlPointTriggerSetup()
    file.bubbleBoundary = CreateBubbleBoundary(file.selectedLocation) 

    foreach(team, v in GetPlayerTeamCountTable())
    {
        array<entity> squad = GetPlayerArrayOfTeam(team) //useless?
    }
    float endTime = Time() + GetCurrentPlaylistVarFloat("round_time", 600)

    while( Time() <= endTime )
	{
        if(file.tdmState == eTDMState.WINNER_DECIDED)
            break
		WaitFrame()
	}
    file.tdmState = eTDMState.IN_PROGRESS
    if(IsValid(file.bubbleBoundary)) file.bubbleBoundary.Destroy()
    VotingPhase()
}


void function _OnPlayerConnected(entity player)
{
    if(!IsValid(player)) return
    readyList.player <- false

    //Give passive regen (pilot blood)
    GivePassive(player, ePassives.PAS_PILOT_BLOOD)
    SetPlayerSettings(player, TDM_PLAYER_SETTINGS)

    if(!IsAlive(player))
    {
        _HandleRespawn(player)
    }

    
    switch(GetGameState())
    {

    case eGameState.WaitingForPlayers:
        print("\n\n\n\n\n\n WATING FOR PLAYERS \n\n\n\n\n\n")
        //player.FreezeControlsOnServer()
        break
    case eGameState.Playing:
        print("\n\n\n\n\n\n PLAYING \n\n\n\n\n\n")
        player.UnfreezeControlsOnServer();
        break
    case eGameState.MapVoting:
        print("\n\n\n\n\n\n MAP VOTING \n\n\n\n\n\n")
        //if(!IsValid(player)) continue;
        //_HandleRespawn(player)
        //MakeInvincible(player)
        //HolsterAndDisableWeapons( player )
        player.SetThirdPersonShoulderModeOn()
        HolsterAndDisableWeapons( player )
        player.UnforceStand()  
        player.UnfreezeControlsOnServer()
        Message(player, "Pre-game", helpMessage(), 15)
        //TpPlayerToSpawnPoint(player)
        //player.UnfreezeControlsOnServer();  
        break
    default: 
        print("\n\n\n\n\n\n DEFAULT \n\n\n\n\n\n")
        break
    }
}

void function _OnPlayerDied(entity victim, entity attacker, var damageInfo) 
{
    switch(GetGameState())
    {
    case eGameState.Playing:

        // What happens to victim 
        void functionref() victimHandleFunc = void function() : (victim, attacker, damageInfo) {
            if(!IsValid(victim)) return
            thread spawnDeathbox(victim)
            victim.p.storedWeapons = StoreWeapons(victim)
            if(IsValid(attacker)) Message(victim,"Killed by " + attacker.GetPlayerName(), "", 2.5, "")
            int reservedTime = 2
            wait reservedTime
            if(Spectator_GetReplayIsEnabled() && IsValid(victim) && ShouldSetObserverTarget( attacker ))
            {
                victim.SetObserverTarget( attacker )
                victim.SetSpecReplayDelay( Spectator_GetReplayDelay() )
                victim.StartObserverMode( OBS_MODE_IN_EYE )
                Remote_CallFunction_NonReplay(victim, "ServerCallback_KillReplayHud_Activate")
            }
            
            wait max(0, Deathmatch_GetRespawnDelay() - reservedTime)
             

            if(IsValid(victim) )
            {
                //_HandleRespawn( victim )
                respawnQueue.append(victim)
            }

        }

        
        // What happens to attacker
        void functionref() attackerHandleFunc = void function() : (victim, attacker, damageInfo)  {
            if(IsValid(attacker) && attacker.IsPlayer() && IsAlive(attacker) && attacker != victim)
            {
                PlayerRestoreHP(attacker, 25, Equipment_GetDefaultShieldHP())
            }
        }
        
        thread victimHandleFunc()
        thread attackerHandleFunc()
        break
    default:

    }
}

void function controlPointLogic(entity controlpoint, entity circle)
{
    string capStatus = "neutral"
    float capProgress = 0.0
    //while(true)
    while(GetGameState() == eGameState.Playing)
    {
        wait 0.75
        int imc_count = 0
        int mil_count = 0
        foreach (player in GetPlayerArray_Alive())
        {   
            if (!player.IsPlayer()) continue
            if(!IsValid(controlpoint)) continue
            
            
            if(Distance(player.GetOrigin(), controlpoint.GetOrigin()) < controlpoint.GetRadius())
            {
                switch (player.GetTeam()) 
                {
                    case TEAM_IMC:
                        imc_count++
                        break;
                    case TEAM_MILITIA:
                        mil_count++
                        break;
                    default:
                        break;
                }    
                if (imc_count > 0 && mil_count == 0 && capStatus != "IMC") thread EmitSoundOnEntityOnlyToPlayer( player, player, "" ) //ADD NICE SOUND
                if (mil_count > 0 && imc_count == 0 && capStatus != "MIL") thread EmitSoundOnEntityOnlyToPlayer( player, player, "" ) //ADD NMICE SOUND

            }
        }
                

        if (imc_count > 0 && mil_count == 0 && capStatus != "IMC")
        {
            if(capProgress >= -1.0) capProgress = capProgress - 0.25  
        }
        if (mil_count > 0 && imc_count == 0 && capStatus != "MIL")
        {
            //Make capture notifications here
            if(capProgress <= 1.0) capProgress = capProgress + 0.25
        } 
        if(capProgress <= -1.0 && capStatus != "IMC")
        { 
            capStatus = "IMC"
            foreach (player in GetPlayerArray()) {
                if (player.GetTeam() == TEAM_MILITIA) Message(player, "Enemy captured the point", "", 3, "ui_callerid_chime_enemy") // ADD NICE SOUND
                if (player.GetTeam() == TEAM_IMC) Message(player, "You captured the point", "", 3, "ui_callerid_chime_friendly") // ADD NICE SOUND
            }                 
        }



        if(capProgress >= 1.0 && capStatus != "MIL")
        {
            capStatus = "MIL"
            foreach (player in GetPlayerArray()) {
                if (player.GetTeam() == TEAM_MILITIA) Message(player, "You captured the point", "", 3, "ui_callerid_chime_friendly") // ADD NICE SOUND
                if (player.GetTeam() == TEAM_IMC) Message(player, "Enemy captured the point", "", 3, "ui_callerid_chime_enemy") // ADD NICE SOUND

            }        
        }


        if(imc_count !=0 && mil_count !=0 && capStatus=="neutral") capStatus="contested"


        if(capStatus == "IMC" && GetGameState() == eGameState.Playing)
        {
            int score = GameRules_GetTeamScore(TEAM_IMC)
            if (!(score == 99 && mil_count != 0))
            {            
            checkIfWon(score, TEAM_MILITIA)
            score ++
            GameRules_SetTeamScore(TEAM_IMC,score)
            if(IsValid(circle)) circle.kv.rendercolor = "20 20 80"
            }
        }

        if(capStatus == "MIL" && GetGameState() == eGameState.Playing)
        {   
            int score = GameRules_GetTeamScore(TEAM_MILITIA)
            if (!(score == 99 && imc_count != 0))
            {   
                checkIfWon(score, TEAM_MILITIA)
                score ++
                GameRules_SetTeamScore(TEAM_MILITIA,score)
                if(IsValid(circle)) circle.kv.rendercolor = "80 20 20"
            }

        }

        if(capStatus == "neutral" && GetGameState() == eGameState.Playing)
        {   
            if(IsValid(circle)) circle.kv.rendercolor = "110 110 110"
        }

        if(capStatus == "contested" && GetGameState() == eGameState.Playing)
        {   
            if(IsValid(circle)) circle.kv.rendercolor = "80 80 15"
        }




        foreach(a in GetPlayerArray())
        {
            Remote_CallFunction_NonReplay(a, "ServerCallback_TDM_PlayerKilled") //lol
        }
    }   
}


void function checkIfWon(int score, int team)
{
    if(score >= SCORE_GOAL_TO_WIN)
    {
        string teamname = ""
        foreach( entity player in GetPlayerArray() )
        {
            if(team == 0) teamname = "No"
            if (team == TEAM_IMC) teamname = "Blue" //RNG ROFL?
            if (team == TEAM_MILITIA) teamname = "Red" //RNG ROFL?
            thread EmitSoundOnEntityOnlyToPlayer( player, player, "diag_ap_aiNotify_winnerFound" )
            Message(player, teamname + " team has won the game!","", 6,"")
            //MakeInvincible(player)
            HolsterAndDisableWeapons( player )
        }
        wait 6
        foreach (player in GetPlayerArray())
        {
            Message(player,"FINAL SCOREBOARD -", "\n         Name: K | D | KD | Damage \n \n" + ScoreboardFinal(), 15, "UI_Menu_RoundSummary_Results")
        }
        wait 12
        file.tdmState = eTDMState.WINNER_DECIDED
    } 
}




/*
  _____ _      _____ ______ _   _ _______    _____ ____  __  __ __  __          _   _ _____   _____ 
  / ____| |    |_   _|  ____| \ | |__   __|  / ____/ __ \|  \/  |  \/  |   /\   | \ | |  __ \ / ____|
 | |    | |      | | | |__  |  \| |  | |    | |   | |  | | \  / | \  / |  /  \  |  \| | |  | | (___  
 | |    | |      | | |  __| | . ` |  | |    | |   | |  | | |\/| | |\/| | / /\ \ | . ` | |  | |\___ \ 
 | |____| |____ _| |_| |____| |\  |  | |    | |___| |__| | |  | | |  | |/ ____ \| |\  | |__| |____) |
  \_____|______|_____|______|_| \_|  |_|     \_____\____/|_|  |_|_|  |_/_/    \_\_| \_|_____/|_____/ 
  
*/
                                                                                                     
                                                                                                     


bool function ClientCommand_EndGame(entity player, array<string> args)
{
    if( !IsServer() ) return false;
    if(IsValid(file.bubbleBoundary)) file.bubbleBoundary.Destroy()

    //file.tdmState = eTDMState.WINNER_DECIDED
    //Message(player," FINAL SCOREBOARD ", "\n         Name: K | D | KD \n \n" + ScoreboardFinal(), 12, "UI_Menu_RoundSummary_Results")
    thread checkIfWon(SCORE_GOAL_TO_WIN,0)
    return true
}

bool function ClientCommand_Ready(entity player, array<string> args)
{
    if (readyList.player == false){ 
    readyList.player <- true
    thread EmitSoundOnEntityOnlyToPlayer( player, player, "UI_Menu_accept" )
    }
    else 
    {
        readyList.player <- false
        thread EmitSoundOnEntityOnlyToPlayer( player, player, "UI_Menu_back" )
    }
    int ready_count = 0
    foreach(item in readyList)
    {
        if(item == true) ready_count ++

    }

    thread Message(player,"Status", "Ready status: " + readyList.player + "\nTotal: " + ready_count + "/" + GetPlayerArray().len() + " ready" , 2.75)
    //print("\n\n\nReady: " + readyList.player)
    //print(readyList)
    return true
}

bool function ClientCommand_ChangeTeam(entity player, array<string> args)
{
    int team = player.GetTeam()
    if (team == TEAM_MILITIA) SetTeam(player, TEAM_IMC)
    if (team == TEAM_IMC) SetTeam(player, TEAM_MILITIA)
    CharSelect(player)
    player.TakeOffhandWeapon(OFFHAND_TACTICAL)
    player.TakeOffhandWeapon(OFFHAND_ULTIMATE)
    return true
}

bool function ClientCommand_SelectMap(entity player, array<string> args)
{
    if( !IsServer() ) return false;
    if(args.len() != 0)
    {
        switch(args[0].tolower())
        {
        case "ttv":
            print("Case = TTV")
            choice = 2
            break
        case "lavacity":
            choice=5
            break
        case "ambush":
            choice=6
            break
        case "overlook":
            choice=7
            break
        case "towersmall":
            choice = 8
            break
        case "towerbig":
            choice = 9
            break
        default: 
            print("\n\n\nInvalid map! Lavacity/Overlook/Ambush/Towersmall/Towerbig")
            break
        }
    } 
    if(args.len() == 0) {
          print("\n\n\nYou must choose a map! Lavacity/Overlook/Ambush/Towersmall/Towerbig")
      }  
    return true

}   

bool function ClientCommand_SpawnDeathbox(entity player, array<string> args)
{
    thread spawnDeathbox(player)
    return true
}

bool function ClientCommand_DestroyDoors(entity player, array<string> args)
{
    foreach (door in GetAllPropDoors())
    {
        door.Destroy()
    }
    return true
}

bool function ClientCommand_Scoreboard(entity player, array<string> args)
//by michae\l/#1125
{
    float ping = player.GetLatency() * 1000 - 40
    if(IsValid(player)) {
        try{
        Message(player, "SCOREBOARD", "\n Name:    K  |   D   |   KD   |   Damage dealt \n" + ScoreboardFinal() + "\n\nYour ping: " + ping.tointeger() + "ms.", 4)
        }catch(e) {}
    }
    return true
}

bool function ClientCommand_ShowLatency(entity player, array<string> args)
//by Retículo Endoplasmático#5955
{
try{
    Message(player,"Latency board", LatencyBoard(), 8)
    }catch(e) {}

return true
}



/*   _____ _____  ______       _______ _____ _   _  _____    _____ _    _ _____ _______ 
  / ____|  __ \|  ____|   /\|__   __|_   _| \ | |/ ____|  / ____| |  | |_   _|__   __|
 | |    | |__) | |__     /  \  | |    | | |  \| | |  __  | (___ | |__| | | |    | |   
 | |    |  _  /|  __|   / /\ \ | |    | | | . ` | | |_ |  \___ \|  __  | | |    | |   
 | |____| | \ \| |____ / ____ \| |   _| |_| |\  | |__| |  ____) | |  | |_| |_   | |   
  \_____|_|  \_\______/_/    \_\_|  |_____|_| \_|\_____| |_____/|_|  |_|_____|  |_|   
                                                                                      
                                                                                      */



entity function CreateBubbleBoundary(LocationSettings location)
{
    array<LocPair> spawns = location.spawns
    
    vector bubbleCenter
    foreach(spawn in spawns)
    {
        bubbleCenter += spawn.origin
    }
    
    bubbleCenter /= spawns.len()

    float bubbleRadius = 0

    foreach(LocPair spawn in spawns)
    {
        if(Distance(spawn.origin, bubbleCenter) > bubbleRadius)
        bubbleRadius = Distance(spawn.origin, bubbleCenter)*0.9
    }
    
    bubbleRadius += GetCurrentPlaylistVarFloat("bubble_radius_padding", 800)

    entity bubbleShield = CreateEntity( "prop_dynamic" )
	bubbleShield.SetValueForModelKey( BUBBLE_BUNKER_SHIELD_COLLISION_MODEL )
    bubbleShield.SetOrigin(bubbleCenter)
    bubbleShield.SetModelScale(bubbleRadius / 235)
    bubbleShield.kv.CollisionGroup = 0
    bubbleShield.kv.rendercolor = "127 73 37"
    DispatchSpawn( bubbleShield )

    thread MonitorBubbleBoundary(bubbleShield, bubbleCenter, bubbleRadius)

    return bubbleShield

}


void function MonitorBubbleBoundary(entity bubbleShield, vector bubbleCenter, float bubbleRadius)
{
    while(IsValid(bubbleShield))
    {

        foreach(player in GetPlayerArray_Alive())
        {
            if(!IsValid(player)) continue
            if(Distance(player.GetOrigin(), bubbleCenter) > bubbleRadius)
            {
				//Remote_CallFunction_Replay( player, "ServerCallback_PlayerTookDamage", 0, 0, 0, 0, DF_BYPASS_SHIELD | DF_DOOMED_HEALTH_LOSS, eDamageSourceId.deathField, null )
                //player.TakeDamage( int( Deathmatch_GetOOBDamagePercent() / 100 * float( player.GetMaxHealth() ) ), null, null, { scriptType = DF_BYPASS_SHIELD | DF_DOOMED_HEALTH_LOSS, damageSourceId = eDamageSourceId.deathField } )
            }
        }
        wait 1
    }
    
}

void function ControlPointTriggerSetup()
{
    entity controlpoint = CreateEntity("trigger_cylinder")
    switch(choice)
    { 
        case(1): //TTV
            controlpoint.SetRadius(500)
            controlpoint.SetAboveHeight(500)
            controlpoint.SetBelowHeight(500)
            controlpoint.SetOrigin(<10396.31, 5856.99, -4233.91>)
            break;
        case(5): //Lava City
            controlpoint.SetRadius(400)
            controlpoint.SetAboveHeight(500)
            controlpoint.SetBelowHeight(500)
            controlpoint.SetOrigin(<24427, -27555, -3453>)
            break;
        case(6): //Ambush
            controlpoint.SetRadius(350)
            controlpoint.SetAboveHeight(500)
            controlpoint.SetBelowHeight(500)
            controlpoint.SetOrigin(<5687, 26748, -4540>)
            break;
        case(7): //Overlook
            controlpoint.SetRadius(235)
            controlpoint.SetAboveHeight(180)
            controlpoint.SetBelowHeight(50)
            controlpoint.SetOrigin(<29265,10405,-3475>)
            break;
        case(8): //Tower Small
            controlpoint.SetRadius(230)
            controlpoint.SetAboveHeight(150)
            controlpoint.SetBelowHeight(20)
            controlpoint.SetOrigin(< -4450.46, 27529.90, -3337.32>)
        case(9): //Tower Big
            controlpoint.SetRadius(270)
            controlpoint.SetAboveHeight(150)
            controlpoint.SetBelowHeight(20)
            controlpoint.SetOrigin(< -20097.85, 12574.88, -3594.01>)

    }
    DispatchSpawn(controlpoint)

    entity circle = CreateEntity( "prop_dynamic" )
    circle.SetOrigin(controlpoint.GetOrigin())
    circle.SetValueForModelKey( BUBBLE_BUNKER_SHIELD_COLLISION_MODEL )
    circle.SetModelScale(controlpoint.GetRadius() / 235)
    circle.kv.rendercolor = "100 100 100"
    circle.kv.CollisionGroup = 0


    circle.SetScriptName("controlPoint")
    DispatchSpawn( circle )


    //thread Point_CreateHUDMarker(circle)
    thread controlPointLogic(controlpoint, circle)
}

/*
   _____ _____   __          ___   _   ______ _    _ _   _  _____ _______ _____ ____  _   _  _____ 
  / ____|  __ \ /\ \        / / \ | | |  ____| |  | | \ | |/ ____|__   __|_   _/ __ \| \ | |/ ____|
 | (___ | |__) /  \ \  /\  / /|  \| | | |__  | |  | |  \| | |       | |    | || |  | |  \| | (___  
  \___ \|  ___/ /\ \ \/  \/ / | . ` | |  __| | |  | | . ` | |       | |    | || |  | | . ` |\___ \ 
  ____) | |  / ____ \  /\  /  | |\  | | |    | |__| | |\  | |____   | |   _| || |__| | |\  |____) |
 |_____/|_| /_/    \_\/  \/   |_| \_| |_|     \____/|_| \_|\_____|  |_|  |_____\____/|_| \_|_____/                                                                                                  
*/                                                                                           

void function SpawnWave()
{
    while(true)
    {
        print(respawnQueue)
        foreach(player in respawnQueue) 
        {
            print(player)
            _HandleRespawn(player)
            respawnQueue.remove(respawnQueue.find(player))
        }
        wait 8
    }
}


void function _HandleRespawn(entity player, bool forceGive = false)
{
    if(!IsValid(player)) return
    CharSelect(player)
    if( player.IsObserver())
    {
        player.StopObserverMode()
        Remote_CallFunction_NonReplay(player, "ServerCallback_KillReplayHud_Deactivate")
    }

    if(!IsAlive(player) || forceGive)
    {

        if(Equipment_GetRespawnKitEnabled())
        {
            DecideRespawnPlayer(player, true)
            CharSelect(player)
            player.TakeOffhandWeapon(OFFHAND_TACTICAL)
            player.TakeOffhandWeapon(OFFHAND_ULTIMATE)
            array<StoredWeapon> weapons = [
                Equipment_GetRespawnKit_PrimaryWeapon(),
                Equipment_GetRespawnKit_SecondaryWeapon(),
                Equipment_GetRespawnKit_Tactical(),
                Equipment_GetRespawnKit_Ultimate()
            ]



            foreach (storedWeapon in weapons)
            {
                if ( !storedWeapon.name.len() ) continue
                printl(storedWeapon.name + " " + storedWeapon.weaponType)
                if( storedWeapon.weaponType == eStoredWeaponType.main)
                    player.GiveWeapon( storedWeapon.name, storedWeapon.inventoryIndex, storedWeapon.mods )
                else
                    player.GiveOffhandWeapon( storedWeapon.name, storedWeapon.inventoryIndex, storedWeapon.mods )
            }
            player.SetActiveWeaponBySlot(eActiveInventorySlot.mainHand, WEAPON_INVENTORY_SLOT_PRIMARY_0)

        }
        else 
        {
            if(!player.p.storedWeapons.len())
            {
                DecideRespawnPlayer(player, true)
                CharSelect(player) 
            }
            else
            {
                DecideRespawnPlayer(player, false)
                CharSelect(player)
                GiveWeaponsFromStoredArray(player, player.p.storedWeapons)
            }
            
        }
    }
    

    SetPlayerSettings(player, TDM_PLAYER_SETTINGS)
    PlayerRestoreHP(player, 100, Equipment_GetDefaultShieldHP())
                
    TpPlayerToSpawnPoint(player)
    thread GrantSpawnImmunity(player, 3)
    
}


void function _HandleRespawnOnLand(entity player)
{
    RemovePlayerMovementEventCallback(player, ePlayerMovementEvents.TOUCH_GROUND, _HandleRespawnOnLand)

    //thread f()
    
}


void function GrantSpawnImmunity(entity player, float duration)
{
    if(!IsValid(player)) return;
    //MakeInvincible(player)
    wait duration
    if(!IsValid(player)) return;
    ClearInvincible(player)
}


LocPair function _GetAppropriateSpawnLocation(entity player)
{
    int ourTeam = player.GetTeam()

    LocPair selectedSpawn = _GetVotingLocation()

    switch(GetGameState())
    {
    case eGameState.MapVoting:
        selectedSpawn = _GetVotingLocation()
        break
    case eGameState.Playing:
        float maxDistToEnemy = 0
        foreach(spawn in file.selectedLocation.spawns)
        {
            vector enemyOrigin = GetClosestEnemyToOrigin(spawn.origin, ourTeam)
            float distToEnemy = Distance(spawn.origin, enemyOrigin)

            if(distToEnemy > maxDistToEnemy)
            {
                maxDistToEnemy = distToEnemy
                selectedSpawn = spawn
            }
        }
        break

    }
    return selectedSpawn
}

vector function GetClosestEnemyToOrigin(vector origin, int ourTeam)
{
    float minDist = -1
    vector enemyOrigin = <0, 0, 0>

    foreach(player in GetPlayerArray_Alive())
    {
        if(player.GetTeam() == ourTeam) continue

        float dist = Distance(player.GetOrigin(), origin)
        if(dist < minDist || minDist < 0)
        {
            minDist = dist
            enemyOrigin = player.GetOrigin()
        }
    }

    return enemyOrigin
}

void function TpPlayerToSpawnPoint(entity player)
{
	
	LocPair loc = _GetAppropriateSpawnLocation(player)

    player.SetOrigin(loc.origin)
    player.SetAngles(loc.angles)

    
    PutEntityInSafeSpot( player, null, null, player.GetOrigin() + <0,0,128>, player.GetOrigin() )
}




/*
  __  __ _____  _____  _____ 
 |  \/  |_   _|/ ____|/ ____|
 | \  / | | | | (___ | |     
 | |\/| | | |  \___ \| |     
 | |  | |_| |_ ____) | |____ 
 |_|  |_|_____|_____/ \_____|
                             
                             
*/


void function Message( entity player, string text, string subText = "", float duration = 7.0, string sound = "" )
{
    string sendMessage
    for ( int textType = 0 ; textType < 2 ; textType++ )
    {
        sendMessage = textType == 0 ? text : subText

        for ( int i = 0; i < sendMessage.len(); i++ )
        {
            Remote_CallFunction_NonReplay( player, "Dev_BuildClientMessage", textType, sendMessage[i] )
        }
    }
    Remote_CallFunction_NonReplay( player, "Dev_PrintClientMessage", duration )
    if ( sound != "" )
        thread EmitSoundOnEntityOnlyToPlayer( player, player, sound )   
        
}


void function spawnDeathbox(entity player)

{    
    entity box = SURVIVAL_CreateDeathBox(player, true)

    LootData data = SURVIVAL_Loot_GetLootDataByRef("armor_pickup_lv3")
    entity drop = SpawnGenericLoot( data.ref, box.GetOrigin(), <0,0,0>, 1 )

    AddToDeathBox(drop,box)


    array<entity> lootArray = box.GetLinkEntArray()


    float destroyWhen = Time() + 30
    while(IsValid(box))
    {
    if (box.GetLinkEntArray()[0] != lootArray[0]) box.Destroy() 
    if(Time() > destroyWhen) box.Destroy()
    wait 1
    }
}


void function PlayerRestoreHP(entity player, float health, float shields)
{
    float newHP = player.GetHealth() + health //maybefixed
    if (newHP > 100) newHP = 100
    player.SetHealth( newHP )
    Inventory_SetPlayerEquipment(player, "helmet_pickup_lv4_abilities", "helmet")

    if(shields == 0) return;
    else if(shields <= 50)
        Inventory_SetPlayerEquipment(player, "armor_pickup_lv1", "armor")
    else if(shields <= 75)
        Inventory_SetPlayerEquipment(player, "armor_pickup_lv2", "armor")
    else if(shields <= 100)
        Inventory_SetPlayerEquipment(player, "armor_pickup_lv3", "armor")
    player.SetShieldHealth( shields )

}


void function CharSelect(entity player)
{
    print("CharSelect!")
    file.characters = clone GetAllCharacters()
    ItemFlavor Picked = file.characters[file.Picked]
    CharacterSelect_AssignCharacter( ToEHI( player ), Picked )

    player.SetBodyModelOverride( $"mdl/humans/class/medium/pilot_medium_generic.rmdl" ) //Dummy body
    //player.SetArmsModelOverride( $"mdl/Weapons/arms/pov_pilot_light_wraith.rmdl") //Wraith arms

    if(player.GetTeam() == TEAM_MILITIA) player.SetSkin(1)
    if(player.GetTeam() == TEAM_IMC) player.SetSkin(3)  

}


void function ScreenFadeToFromBlack(entity player, float fadeTime = 1, float holdTime = 1)
{
    if( IsValid( player ) )
        ScreenFadeToBlack(player, fadeTime / 2, holdTime / 2)
    wait fadeTime
    if( IsValid( player ) )
        ScreenFadeFromBlack(player, fadeTime / 2, holdTime / 2)
}


void function _OnPropDynamicSpawned(entity prop)
{
    file.playerSpawnedProps.append(prop)



    /*
    //foreach(player in GetPlayerArray())
    //{
        //Remote_CallFunction_NonReplay(player, "ServerCallback_PointCreated", prop) //what the fuck is this
    //}*/
}


void function DestroyPlayerProps()
{
    foreach(prop in file.playerSpawnedProps)
    {
        if(IsValid(prop))
            prop.Destroy()
    }
    file.playerSpawnedProps.clear()
}


/*   _____    _____    ____    _____    ______   ____     ____               _____    _____  
  / ____|  / ____|  / __ \  |  __ \  |  ____| |  _ \   / __ \      /\     |  __ \  |  __ \ 
 | (___   | |      | |  | | | |__) | | |__    | |_) | | |  | |    /  \    | |__) | | |  | |
  \___ \  | |      | |  | | |  _  /  |  __|   |  _ <  | |  | |   / /\ \   |  _  /  | |  | |
  ____) | | |____  | |__| | | | \ \  | |____  | |_) | | |__| |  / ____ \  | | \ \  | |__| |
 |_____/   \_____|  \____/  |_|  \_\ |______| |____/   \____/  /_/    \_\ |_|  \_\ |_____/ 
                                                                                           
                                                                                           */



entity function GetBestPlayer() 
{
    
    int bestScore = 0
    entity bestPlayer

    foreach(player in GetPlayerArray()) {
        if(!IsValid(player)) continue
        if (player.GetPlayerGameStat( PGS_KILLS ) > bestScore) {
            bestScore = player.GetPlayerGameStat( PGS_KILLS )
            bestPlayer = player
            
        }
    }
    return bestPlayer
}

int function GetBestPlayerScore() 
{
    int bestScore = 0
    foreach(player in GetPlayerArray()) {
        if(!IsValid(player)) continue
        if (player.GetPlayerGameStat( PGS_KILLS ) > bestScore) bestScore = player.GetPlayerGameStat( PGS_KILLS )
    }
    return bestScore
}

string function GetBestPlayerName()

{
    entity player = GetBestPlayer()
    if(!IsValid(player)) return "-still nobody-"
    string champion = player.GetPlayerName()
    return champion
}

float function getkd(int kills, int deaths)
{
    float kd
    if(deaths == 0) return kills.tofloat();
    kd = kills.tofloat() / deaths.tofloat()
    return kd
}

string function Scoreboard()
//Este solo muestra los tres primeros
//Thanks marumaru（vesslanG）#3285
{
array <PlayerInfo> playersInfo = []
        foreach(player in GetPlayerArray())
        {
            PlayerInfo p
            p.name = player.GetPlayerName()
            p.team = player.GetTeam()
            p.score = player.GetPlayerGameStat( PGS_KILLS )
            p.deaths = player.GetPlayerGameStat( PGS_DEATHS )
            p.kd = getkd(p.score,p.deaths)
            playersInfo.append(p)
        }
        playersInfo.sort(ComparePlayerInfo)
        
        string msg = ""
        for(int i = 0; i < playersInfo.len(); i++)
        {   
            PlayerInfo p = playersInfo[i]
            switch(i)
            {
                case 0:
                    msg = msg + "1. " + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + "\n"
                    break
                case 1:
                    msg = msg + "2. " + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + "\n"
                    break
                case 2:
                    msg = msg + "3. " + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + "\n"
                    break
                default:
                    break
            }
        }
        return msg
}
    
string function ScoreboardFinal()
//Este muestra el scoreboard completo
//Thanks marumaru（vesslanG）#3285
{
array<PlayerInfo> playersInfo = []
        foreach(player in GetPlayerArray())
        {
            PlayerInfo p
            p.name = player.GetPlayerName()
            p.team = player.GetTeam()
            p.score = player.GetPlayerGameStat( PGS_KILLS )
            p.deaths = player.GetPlayerGameStat( PGS_DEATHS )
            p.kd = getkd(p.score,p.deaths)
            p.damage = int(player.p.playerDamageDealt)
            p.lastLatency = int(player.GetLatency()* 1000)
            playersInfo.append(p)
        }
        playersInfo.sort(ComparePlayerInfo)
        string msg = ""
        for(int i = 0; i < playersInfo.len(); i++)
        {   
            PlayerInfo p = playersInfo[i]
            switch(i)
            {
                case 0:
                     msg = msg + "1. " + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + " | " + p.damage + "\n"
                    break
                case 1:
                    msg = msg + "2. " + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + " | " + p.damage + "\n"
                    break
                case 2:
                    msg = msg + "3. " + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + " | " + p.damage + "\n"
                    break
                default:
                    msg = msg + p.name + ":   " + p.score + " | " + p.deaths + " | " + p.kd + " | " + p.damage + "\n"
                    break
            }
        }
        return msg
}
    
int function ComparePlayerInfo(PlayerInfo a, PlayerInfo b)
{
    if(a.score < b.score) return 1;
    else if(a.score > b.score) return -1;
    return 0; 
}

void function ResetAllPlayerStats()
{
    foreach(player in GetPlayerArray()) {
        if(!IsValid(player)) continue
        ResetPlayerStats(player)
    }
}

void function ResetPlayerStats(entity player) 
{
    player.SetPlayerGameStat( PGS_SCORE, 0 )
    player.SetPlayerGameStat( PGS_DEATHS, 0)
    player.SetPlayerGameStat( PGS_TITAN_KILLS, 0)
    player.SetPlayerGameStat( PGS_KILLS, 0)
    player.SetPlayerGameStat( PGS_PILOT_KILLS, 0)
    player.SetPlayerGameStat( PGS_ASSISTS, 0)
    player.SetPlayerGameStat( PGS_ASSAULT_SCORE, 0)
    player.SetPlayerGameStat( PGS_DEFENSE_SCORE, 0)
    player.SetPlayerGameStat( PGS_ELIMINATED, 0)
}

string function helpMessage() 
{
    return "\n\n          CONSOLE COMMANDS:\n- ready\n- change_team\n- scoreboard \n- latency\n- select_map (host only)\n- end_game (host only)"
}



string function LatencyBoard()
//By Café
{
array<PlayerInfo> playersInfo = []
        foreach(player in GetPlayerArray())
        {
            PlayerInfo p
            p.name = player.GetPlayerName()
            p.score = player.GetPlayerGameStat( PGS_KILLS )
            p.lastLatency = int(player.GetLatency()* 1000) - 40
            playersInfo.append(p)
        }
        playersInfo.sort(ComparePlayerInfo)
        string msg = ""
        for(int i = 0; i < playersInfo.len(); i++)
        {
            PlayerInfo p = playersInfo[i]
            switch(i)
            {
                case 0:
                     msg = msg + "1. " + p.name + ":   " + p.lastLatency  + "ms \n"
                    break
                case 1:
                    msg = msg + "2. " + p.name + ":   " + p.lastLatency  + "ms \n"
                    break
                case 2:
                    msg = msg + "3. " + p.name + ":   " + p.lastLatency  + "ms \n"
                    break
                default:
                    msg = msg + p.name + ":   " + p.lastLatency + "ms \n"
                    break
            }
        }
        return msg
}