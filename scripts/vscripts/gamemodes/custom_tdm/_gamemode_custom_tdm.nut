global function _CustomTDM_Init
global function _RegisterLocation

global table<entity,bool> readyList = {}
global int choice = 3


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

    
    array<string> whitelistedWeapons

    entity bubbleBoundary
} file;


void function _CustomTDM_Init()
{
    AddCallback_OnClientConnected( void function(entity player) { thread _OnPlayerConnected(player) } )
    AddCallback_OnPlayerKilled(void function(entity victim, entity attacker, var damageInfo) {thread _OnPlayerDied(victim, attacker, damageInfo)})


    AddClientCommandCallback("end_game", ClientCommand_EndGame)
    AddClientCommandCallback("ready", ClientCommand_Ready)
    AddClientCommandCallback("change_team", ClientCommand_ChangeTeam)
    AddClientCommandCallback("select_map",ClientCommand_SelectMap)
    AddClientCommandCallback("spawn_deathbox",Clientcommand_SpawnDeathbox)


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

void function _OnPropDynamicSpawned(entity prop)
{
    file.playerSpawnedProps.append(prop)
    
}
void function RunTDM()
{
    WaitForGameState(eGameState.Playing)
    //AddSpawnCallback("prop_dynamic", _OnPropDynamicSpawned)

    for(; ; )
    {
        VotingPhase();
        StartRound();
    }
    WaitForever()
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
            Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 6, eTDMAnnounce.VOTING_PHASE)
            TpPlayerToSpawnPoint(player)
            player.UnfreezeControlsOnServer();      
        }


        int ready_count = 0
        while(ready_count < GetPlayerArray().len())
        {
            foreach(item in readyList)
            {
                if(item == true) ready_count ++
            }
        wait 1      
        }


        file.selectedLocation = file.locationSettings[choice]
    }
}   

void function StartRound() 
{
    SetGameState(eGameState.Playing)
    foreach(player in GetPlayerArray())
    {   
        if( IsValid( player ) )
        {
            Remote_CallFunction_NonReplay(player, "ServerCallback_TDM_DoAnnouncement", 0, eTDMAnnounce.ROUND_START)
            player.FreezeControlsOnServer()
            thread ScreenFadeFromBlack(player, 0.5, 0.5)
            TpPlayerToSpawnPoint(player)
            Message(player,"Starting in 10","", 7,"")


            wait 7
            Message(player,"Starting in 3","", 3,"")
            wait 3
            ClearInvincible(player)
            DeployAndEnableWeapons(player)
            player.UnforceStand()  
            player.UnfreezeControlsOnServer()   


            //AddPlayerMovementEventCallback(player, ePlayerMovementEvents.TOUCH_GROUND, _HandleRespawnOnLand)
        }
        
    }

    AddSpawnCallback("prop_dynamic", _OnPropDynamicSpawned)
    AddSpawnCallback("trigger_cylinder", _OnPropDynamicSpawned)

    
    ControlPointTriggerSetup()
    file.bubbleBoundary = CreateBubbleBoundary(file.selectedLocation) 

    foreach(team, v in GetPlayerTeamCountTable())
    {
        array<entity> squad = GetPlayerArrayOfTeam(team)
    }
    float endTime = Time() + GetCurrentPlaylistVarFloat("round_time", 480)

    while( Time() <= endTime )
	{
        if(file.tdmState == eTDMState.WINNER_DECIDED)
            break
		WaitFrame()
	}
    file.tdmState = eTDMState.IN_PROGRESS

    if(IsValid(file.bubbleBoundary)) file.bubbleBoundary.Destroy()
}

void function _HandleRespawnOnLand(entity player)
{
    RemovePlayerMovementEventCallback(player, ePlayerMovementEvents.TOUCH_GROUND, _HandleRespawnOnLand)

    //thread f()
    
}
void function ScreenFadeToFromBlack(entity player, float fadeTime = 1, float holdTime = 1)
{
    if( IsValid( player ) )
        ScreenFadeToBlack(player, fadeTime / 2, holdTime / 2)
    wait fadeTime
    if( IsValid( player ) )
        ScreenFadeFromBlack(player, fadeTime / 2, holdTime / 2)
}

bool function ClientCommand_EndGame(entity player, array<string> args)
{
    if( !IsServer() ) return false;
    if(IsValid(file.bubbleBoundary)) file.bubbleBoundary.Destroy()
    file.tdmState = eTDMState.WINNER_DECIDED
    SetGameState(eGameState.MapVoting)
    return true
}

bool function ClientCommand_Ready(entity player, array<string> args)
{
    if (readyList.player == false) readyList.player <- true
    else readyList.player <- false
    print("\n\n\nReady: " + readyList.player)
    return true
}

bool function ClientCommand_ChangeTeam(entity player, array<string> args)
{
    int team = player.GetTeam()
    if (team == TEAM_MILITIA) SetTeam(player, TEAM_IMC)
    if (team == TEAM_IMC) SetTeam(player, TEAM_MILITIA)
    print("\n\n\nYou're now on team: " + team)
    return true
}

bool function ClientCommand_SelectMap(entity player, array<string> args) //CRASHES IF NO ARG !!!
{
    if( !IsServer() ) return false;
    if(args.len() != 0)
    {
        switch(args[0])
        {
        case "TTV":
            print("Case = TTV")
            choice = 2
            break
        case "LavaCity":
            choice=5
            break
        case "Ambush":
            choice=6
            break
        case "Overlook":
            choice=7
            break
        default: 
            print("\n\n\nInvalid map! LavaCity/Overlook/Ambush")
            break
        }
    } 
    if(args.len() == 0) {
          print("\n\n\nYou must choose a map! LavaCity/Overlook/Ambush")
      }  
    return true

}   
bool function Clientcommand_SpawnDeathbox(entity player, array<string> args)
{
    spawnDeathbox(player)
    return true
}



void function _OnPlayerConnected(entity player)
{
    if(!IsValid(player)) return
    readyList.player <- false

    //Give passive regen (pilot blood)
    GivePassive(player, ePassives.PAS_PILOT_BLOOD)
    //SetPlayerSettings(player, TDM_PLAYER_SETTINGS)

    if(!IsAlive(player))
    {
        _HandleRespawn(player)
    }

    
    switch(GetGameState())
    {

    case eGameState.WaitingForPlayers:
        player.FreezeControlsOnServer()
        break
    case eGameState.Playing:
        player.UnfreezeControlsOnServer();
        break
    case eGameState.MapVoting:
        break
    default: 
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
            
            victim.p.storedWeapons = StoreWeapons(victim)
            
            float reservedTime = max(1, Deathmatch_GetRespawnDelay() - 1)// so we dont immediately go to killcam
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
                _HandleRespawn( victim )
            }

        }

        
        // What happens to attacker
        void functionref() attackerHandleFunc = void function() : (victim, attacker, damageInfo)  {
            if(IsValid(attacker) && attacker.IsPlayer() && IsAlive(attacker) && attacker != victim)
            {
                PlayerRestoreHP(attacker, 100, Equipment_GetDefaultShieldHP())
            }
        }
        
        thread victimHandleFunc()
        thread attackerHandleFunc()
        break
    default:

    }
}

void function _HandleRespawn(entity player, bool forceGive = false)
{
    if(!IsValid(player)) return

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
            }
            else
            {
                DecideRespawnPlayer(player, false)
                GiveWeaponsFromStoredArray(player, player.p.storedWeapons)
            }
            
        }
    }
    
    SetPlayerSettings(player, TDM_PLAYER_SETTINGS)
    PlayerRestoreHP(player, 100, Equipment_GetDefaultShieldHP())
                
    TpPlayerToSpawnPoint(player)
    thread GrantSpawnImmunity(player, 3)
}


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
        bubbleRadius = Distance(spawn.origin, bubbleCenter)
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



void function PlayerRestoreHP(entity player, float health, float shields)
{
    player.SetHealth( health )
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

void function GrantSpawnImmunity(entity player, float duration)
{
    if(!IsValid(player)) return;
    MakeInvincible(player)
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


bool function ClientCommand_GiveWeapon(entity player, array<string> args)
{
    if(args.len() < 2) return false;

    bool foundMatch = false


    foreach(weaponName in file.whitelistedWeapons)
    {
        if(args[1] == weaponName)
        {
            foundMatch = true
            break
        }
    }

    if(file.whitelistedWeapons.find(args[1]) == -1 && file.whitelistedWeapons.len()) return false

    entity weapon

    try {
        entity primary = player.GetNormalWeapon( WEAPON_INVENTORY_SLOT_PRIMARY_0 )
        entity secondary = player.GetNormalWeapon( WEAPON_INVENTORY_SLOT_PRIMARY_1 )
        entity tactical = player.GetOffhandWeapon( OFFHAND_TACTICAL )
        entity ultimate = player.GetOffhandWeapon( OFFHAND_ULTIMATE )
        switch(args[0]) 
        {
            case "p":
            case "primary":
                if( IsValid( primary ) ) player.TakeWeaponByEntNow( primary )
                weapon = player.GiveWeapon(args[1], WEAPON_INVENTORY_SLOT_PRIMARY_0)
                break
            case "s":
            case "secondary":
                if( IsValid( secondary ) ) player.TakeWeaponByEntNow( secondary )
                weapon = player.GiveWeapon(args[1], WEAPON_INVENTORY_SLOT_PRIMARY_1)
                break
            case "t":
            case "tactical":
                if( IsValid( tactical ) ) player.TakeOffhandWeapon( OFFHAND_TACTICAL )
                weapon = player.GiveOffhandWeapon(args[1], OFFHAND_TACTICAL)
                break
            case "u":
            case "ultimate":
                if( IsValid( ultimate ) ) player.TakeOffhandWeapon( OFFHAND_ULTIMATE )
                weapon = player.GiveOffhandWeapon(args[1], OFFHAND_ULTIMATE)
                break
        }
    }
    catch( e1 ) { }

    if( args.len() > 2 )
    {
        try {
            weapon.SetMods(args.slice(2, args.len()))
        }
        catch( e2 ) {
            print(e2)
        }
    }
    
    if( IsValid(weapon) && !weapon.IsWeaponOffhand() ) player.SetActiveWeaponBySlot(eActiveInventorySlot.mainHand, GetSlotForWeapon(player, weapon))
    return true
    
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

    }
    DispatchSpawn(controlpoint)

    entity circle = CreateEntity( "prop_dynamic" )
    circle.SetOrigin(controlpoint.GetOrigin())
    circle.SetValueForModelKey( BUBBLE_BUNKER_SHIELD_COLLISION_MODEL )
    circle.SetModelScale(controlpoint.GetRadius() / 235)
    circle.kv.rendercolor = "100 100 100"
    circle.kv.CollisionGroup = 0

    DispatchSpawn( circle )

    thread controlPointLogic(controlpoint, circle)
}

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
    //if ( sound != "" )
        //thread EmitSoundOnEntityOnlyToPlayer( player, player, sound )   
        
}



void function controlPointLogic(entity controlpoint, entity circle)
{
    string capStatus = "neutral"
    float capProgress = 0.0
    //while(true)
    while(GetGameState() == eGameState.Playing)
    {
        wait 1
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
            }
        }
                

        if (imc_count > 0 && mil_count == 0 && capStatus != "IMC")
        {
            if(capProgress >= -1.0) capProgress = capProgress - 0.2  
        }
        if (mil_count > 0 && imc_count == 0 && capStatus != "MIL")
        {
            //Make capture notifications here
            if(capProgress <= 1.0) capProgress = capProgress + 0.2
        } 
        if(capProgress <= -1.0) capStatus = "IMC"
        if(capProgress >= 1.0) capStatus = "MIL"

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
            if(IsValid(circle)) circle.kv.rendercolor = "80 80 5"
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
            if (team == 2) teamname = "Red"
            if (team == 3) teamname = "Blue"
            thread EmitSoundOnEntityOnlyToPlayer( player, player, "diag_ap_aiNotify_winnerFound" )
            Message(player, teamname + " team has won the game!","", 6,"")
            MakeInvincible(player)
            HolsterAndDisableWeapons( player )
        }
        wait 10
        file.tdmState = eTDMState.WINNER_DECIDED
        SetGameState(eGameState.MapVoting)
    } 
}


void function spawnDeathbox(entity player)
{
    /*entity box = SURVIVAL_CreateDeathBox(player, false)
    array<entity> lootArray = GetEntArrayByClass_Expensive("prop_survival")
    //entity armour = lootArray.find(armor_pickup_lv3)
    print("lootarray length: " + lootArray.len())
    //print(armour)
        foreach( loot in lootArray )
        {
            print("abc")
            AddToDeathBox( loot, box )
        }
    //AddToDeathBox("armor_pickup_lv3",box)*/
}