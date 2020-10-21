#pragma semicolon 1
#pragma newdecls required

#define MAX_ZONE_NAME_LENGTH 128
#define MAX_ZONE_TYPE_LENGTH 64

#define MAX_EFFECT_NAME_LENGTH 128

#define MAX_KEY_NAME_LENGTH 128
#define MAX_KEY_VALUE_LENGTH 128

#define MAX_EFFECT_CALLBACKS 3
#define EFFECT_CALLBACK_ONENTERZONE 0
#define EFFECT_CALLBACK_ONACTIVEZONE 1
#define EFFECT_CALLBACK_ONLEAVEZONE 2

#define DEFAULT_MODELINDEX "sprites/laserbeam.vmt"
#define DEFAULT_HALOINDEX "materials/sprites/halo.vmt"
#define ZONE_MODEL "models/error.mdl"

#define ZONE_TYPES 3
#define ZONE_TYPE_NONE -1
#define ZONE_TYPE_BOX 0
#define ZONE_TYPE_CIRCLE 1
#define ZONE_TYPE_POLY 2

#define MAX_ENTITY_LIMIT 4096

#define TIMER_INTERVAL 0.1
#define TE_LIFE TIMER_INTERVAL+0.1
#define TE_STARTFRAME 0
#define TE_FRAMERATE 0
#define TE_FADELENGTH 0
#define TE_AMPLITUDE 0.0
#define TE_WIDTH 1.0
#define TE_ENDWIDTH TE_WIDTH
#define TE_SPEED 0
#define TE_FLAGS 0

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <multicolors>

ConVar g_cPrecisionValue = null;
ConVar g_cRegenerateSpam = null;
ConVar g_cDefaultHeight = null;

enum struct eForwards
{
	GlobalForward QueueEffects_Post;
	GlobalForward StartTouchZone;
	GlobalForward TouchZone;
	GlobalForward EndTouchZone;
	GlobalForward StartTouchZone_Post;
	GlobalForward TouchZone_Post;
	GlobalForward EndTouchZone_Post;
}

eForwards Forward;

bool g_bLate;

KeyValues g_kvConfig = null;
int g_iRegenerationTime = -1;


ArrayList g_aColors = null;
StringMap g_smColorData = null;

int g_iDefaultModelIndex = -1;
int g_iDefaultHaloIndex = -1;

//Entities Data
ArrayList g_aZoneEntities = null;

enum struct eEntityData
{
	float Radius;
	int Color[4];
	StringMap Effects;
	ArrayList PointsData;
	float PointsHeight;
	float PointsDistance;
	float PointsMin[3];
	float PointsMax[3];
}

eEntityData Zone[MAX_ENTITY_LIMIT];

//Effects Data
StringMap g_smEffectCalls = null;
StringMap g_smEffectKeys = null;
ArrayList g_aEffectsList = null;

//Create Zones Data
enum struct eCreateZone
{
	char Name[MAX_ZONE_NAME_LENGTH];
	int Type;
	float Start[3];
	float End[3];
	float Radius;
	char Color[64];
	int iColors[4];
	ArrayList PointsData;
	float PointsHeight;
	StringMap Effects;
	bool Display;
	bool SetName;
}

eCreateZone CZone[MAXPLAYERS + 1];

bool g_bEffectKeyValue[MAXPLAYERS + 1];
int g_iEffectKeyValue_Entity[MAXPLAYERS + 1];
char g_sEffectKeyValue_Effect[MAXPLAYERS + 1][MAX_EFFECT_NAME_LENGTH];
char g_sEffectKeyValue_EffectKey[MAXPLAYERS + 1][MAX_KEY_NAME_LENGTH];
int g_iEditingName[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
bool g_bIsInZone[MAXPLAYERS + 1][MAX_ENTITY_LIMIT];
bool g_bIsInsideZone[MAXPLAYERS + 1][MAX_ENTITY_LIMIT];
bool g_bIsInsideZone_Post[MAXPLAYERS + 1][MAX_ENTITY_LIMIT];

public Plugin myinfo =
{
	name = "Zones Manager - Core",
	author = "Bara (Original author: Drixevel)",
	description = "A sourcemod plugin with rich features for dynamic zone development.",
	version = "1.1.0",
	url = "github.com/Bara"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("zones_manager");

	CreateNative("ZonesManager_Register_Effect", Native_Register_Effect);
	CreateNative("ZonesManager_Register_Effect_Key", Native_Register_Effect_Key);
	CreateNative("ZonesManager_Request_QueueEffects", Native_Request_QueueEffects);
	CreateNative("ZonesManager_IsClientInZone", Native_IsClientInZone);
	CreateNative("ZonesManager_TeleportClientToZone", Native_TeleportClientToZone);

	Forward.QueueEffects_Post = new GlobalForward("ZonesManager_OnQueueEffects_Post", ET_Ignore);
	Forward.StartTouchZone = new GlobalForward("ZonesManager_OnStartTouchZone", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	Forward.TouchZone = new GlobalForward("ZonesManager_OnTouchZone", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	Forward.EndTouchZone = new GlobalForward("ZonesManager_OnEndTouchZone", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	Forward.StartTouchZone_Post = new GlobalForward("ZonesManager_OnStartTouchZone_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);
	Forward.TouchZone_Post = new GlobalForward("ZonesManager_OnTouchZone_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);
	Forward.EndTouchZone_Post = new GlobalForward("ZonesManager_OnEndTouchZone_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);

	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	// LoadTranslations("zonesmanager.phrases");

	g_cPrecisionValue = CreateConVar("zones_manager_precision_offset", "10.0", "Default value to use when setting a zones precision area.", FCVAR_NOTIFY, true, 0.0);
	g_cRegenerateSpam = CreateConVar("zones_manager_regenerate_spam", "10", "How long should zone regenerations restricted after zone regeneation? (0 to disable this feature)", _, true, 0.0);
	g_cDefaultHeight = CreateConVar("zones_manager_default_height", "256", "Default height for circles and polygons zones (Default: 256)");

	HookEventEx("teamplay_round_start", Event_OnRoundStart);
	HookEventEx("round_start", Event_OnRoundStart);

	RegAdminCmd("sm_zone", Command_EditZoneMenu, ADMFLAG_ROOT, "Edit a certain zone that you're standing in.");
	RegAdminCmd("sm_editzone", Command_EditZoneMenu, ADMFLAG_ROOT, "Edit a certain zone that you're standing in.");
	RegAdminCmd("sm_editzonemenu", Command_EditZoneMenu, ADMFLAG_ROOT, "Edit a certain zone that you're standing in.");
	RegAdminCmd("sm_zones", Command_OpenZonesMenu, ADMFLAG_ROOT, "Display the zones manager menu.");
	RegAdminCmd("sm_zonesmenu", Command_OpenZonesMenu, ADMFLAG_ROOT, "Display the zones manager menu.");
	RegAdminCmd("sm_teleporttozone", Command_TeleportToZone, ADMFLAG_ROOT, "Teleport to a specific zone by name or by menu.");
	RegAdminCmd("sm_regeneratezones", Command_RegenerateZones, ADMFLAG_ROOT, "Regenerate all zones on the map.");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_ROOT, "Delete all zones on the map.");
	RegAdminCmd("sm_reloadeffects", Command_ReloadEffects, ADMFLAG_ROOT, "Reload all effects data and their callbacks.");

	g_aZoneEntities = new ArrayList();

	g_smEffectCalls = new StringMap();
	g_smEffectKeys = new StringMap();
	g_aEffectsList = new ArrayList(ByteCountToCells(MAX_EFFECT_NAME_LENGTH));

	g_aColors = new ArrayList(ByteCountToCells(64));
	g_smColorData = new StringMap();

	g_iRegenerationTime = -1;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int x = MaxClients; x < MAX_ENTITY_LIMIT; x++)
		{
			g_bIsInZone[i][x] = false;
		}
	}

	ReparseMapZonesConfig();

	CreateTimer(TIMER_INTERVAL, Timer_DisplayZones, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	g_iRegenerationTime = -1;
	g_iDefaultModelIndex = PrecacheModel(DEFAULT_MODELINDEX, true);
	g_iDefaultHaloIndex = PrecacheModel(DEFAULT_HALOINDEX, true);
	PrecacheModel(ZONE_MODEL, true);

	LogMessage("Deleting current zones map configuration from memory.");

	ReparseMapZonesConfig();

	for (int i = 1; i <= MaxClients; i++)
	{
		for (int x = MaxClients; x < MAX_ENTITY_LIMIT; x++)
		{
			g_bIsInZone[i][x] = false;
		}
	}
}

public void OnMapEnd()
{
	SaveMapConfig();
	delete g_kvConfig;
}

void ReparseMapZonesConfig(bool delete_config = false)
{
	delete g_kvConfig;

	char sFolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFolder, sizeof(sFolder), "data/zones/");
	CreateDirectory(sFolder, 511);

	char sMap[32];
	GetCurrentMap(sMap, sizeof(sMap));

	char sFile[PLATFORM_MAX_PATH];
	Format(sFile, sizeof(sFile), "%s%s.cfg", sFolder, sMap);

	if (delete_config)
	{
		DeleteFile(sFile);
	}

	LogMessage("Creating keyvalues for the new map before pulling new map zones info.");
	g_kvConfig = new KeyValues("zones_manager");

	if (FileExists(sFile))
	{
		LogMessage("Config exists, retrieving the zones...");
		g_kvConfig.ImportFromFile(sFile);
	}
	else
	{
		LogMessage("Config doesn't exist, creating new zones config for the map: %s", sMap);
		KeyValuesToFile(g_kvConfig, sFile);
	}

	LogMessage("New config successfully loaded.");
}

public void OnConfigsExecuted()
{
	ParseColorsData();

	if (g_bLate)
	{
		SpawnAllZones();

		g_bLate = false;
	}
}

public void OnAllPluginsLoaded()
{
	QueueEffects();
}

void QueueEffects(bool reset = true)
{
	if (reset)
	{
		for (int i = 0; i < g_aEffectsList.Length; i++)
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			g_aEffectsList.GetString(i, sEffect, sizeof(sEffect));

			Handle callbacks[MAX_EFFECT_CALLBACKS];
			g_smEffectCalls.GetArray(sEffect, callbacks, sizeof(callbacks));

			for (int x = 0; x < MAX_EFFECT_CALLBACKS; x++)
			{
				delete callbacks[x];
			}
		}

		g_smEffectCalls.Clear();
		g_aEffectsList.Clear();
	}

	Call_StartForward(Forward.QueueEffects_Post);
	Call_Finish();
}

public void OnPluginEnd()
{
	ClearAllZones();
}

public void OnClientDisconnect(int client)
{
	for (int i = 0; i < MAX_ENTITY_LIMIT; i++)
	{
		g_bIsInZone[client][i] = false;
	}
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	RegenerateZones();
}

void ClearAllZones()
{
	for (int i = 0; i < g_aZoneEntities.Length; i++)
	{
		int zone = EntRefToEntIndex(g_aZoneEntities.Get(i));

		if (IsValidEntity(zone))
		{
			StringMapSnapshot snap1 = Zone[zone].Effects.Snapshot();
			char sKey[128];
			for (int j = 0; j < snap1.Length; j++)
			{
				snap1.GetKey(j, sKey, sizeof(sKey));

				StringMap temp = null;
				Zone[zone].Effects.GetValue(sKey, temp);
				delete temp;
			}
			delete snap1;
			delete Zone[zone].Effects;
			delete Zone[zone].PointsData;

			RemoveEntity(zone);
		}
	}

	g_aZoneEntities.Clear();
}

void SpawnAllZones()
{
	if (g_kvConfig == null)
	{
		return;
	}

	LogMessage("Spawning all zones...");

	g_kvConfig.Rewind();
	if (g_kvConfig.GotoFirstSubKey())
	{
		do
		{
			char sName[MAX_ZONE_NAME_LENGTH];
			g_kvConfig.GetSectionName(sName, sizeof(sName));
			SpawnAZone(sName);
		}
		while(g_kvConfig.GotoNextKey());
	}

	LogMessage("Zones have been spawned.");
}

int SpawnAZone(const char[] name)
{
	if (g_kvConfig == null)
	{
		return -1;
	}

	g_kvConfig.Rewind();
	if (g_kvConfig.JumpToKey(name))
	{
		char sType[MAX_ZONE_TYPE_LENGTH];
		g_kvConfig.GetString("type", sType, sizeof(sType));
		int type = GetZoneTypeByName(sType);

		float vStartPosition[3];
		g_kvConfig.GetVector("start", vStartPosition);

		float vEndPosition[3];
		g_kvConfig.GetVector("end", vEndPosition);

		bool bDisplay = view_as<bool>(g_kvConfig.GetNum("display"));

		float fRadius = g_kvConfig.GetFloat("radius");

		int iColor[4] = {0, 255, 255, 255};
		g_kvConfig.GetColor("color", iColor[0], iColor[1], iColor[2], iColor[3]);

		float points_height = g_kvConfig.GetFloat("points_height", g_cDefaultHeight.FloatValue);

		ArrayList points = new ArrayList(3);
		if (g_kvConfig.JumpToKey("points") && g_kvConfig.GotoFirstSubKey())
		{
			do
			{
				float coordinates[3];
				g_kvConfig.GetVector(NULL_STRING, coordinates);

				points.PushArray(coordinates, 3);
			}
			while (g_kvConfig.GotoNextKey());

			g_kvConfig.GoBack();
			g_kvConfig.GoBack();
		}

		StringMap effects = new StringMap();
		if (g_kvConfig.JumpToKey("effects") && g_kvConfig.GotoFirstSubKey())
		{
			do
			{
				char sEffect[256];
				g_kvConfig.GetSectionName(sEffect, sizeof(sEffect));

				StringMap effect_data = new StringMap();

				if (g_kvConfig.GotoFirstSubKey(false))
				{
					do
					{
						char sKey[256];
						g_kvConfig.GetSectionName(sKey, sizeof(sKey));

						char sValue[256];
						g_kvConfig.GetString(NULL_STRING, sValue, sizeof(sValue));

						effect_data.SetString(sKey, sValue);
					}
					while (g_kvConfig.GotoNextKey(false));

					g_kvConfig.GoBack();
				}

				effects.SetValue(sEffect, effect_data);
			}
			while (g_kvConfig.GotoNextKey());

			g_kvConfig.GoBack();
			g_kvConfig.GoBack();
		}

		eCreateZone zone;
		strcopy(zone.Name, sizeof(eCreateZone::Name), name);
		zone.Type = type;
		zone.Start = vStartPosition;
		zone.End = vEndPosition;
		zone.Radius = fRadius;
		zone.iColors = iColor;
		zone.PointsData = points;
		zone.PointsHeight = points_height;
		zone.Effects = effects;
		zone.Display = bDisplay;
		return CreateZone(zone);
	}

	return -1;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (strlen(sArgs) == 0)
	{
		return;
	}

	if (StrContains(sArgs, "!cancel", true) != -1)
	{
		if (CZone[client].SetName)
		{
			CZone[client].SetName = false;
			OpenCreateZonesMenu(client);
		}
		else if (g_bEffectKeyValue[client])
		{
			g_bEffectKeyValue[client] = false;
			ListZoneEffectKeys(client, g_iEffectKeyValue_Entity[client], g_sEffectKeyValue_Effect[client]);
		}
		else if (g_iEditingName[client] != INVALID_ENT_REFERENCE)
		{
			int entity = EntRefToEntIndex(g_iEditingName[client]);
			g_iEditingName[client] = INVALID_ENT_REFERENCE;
			OpenZonePropertiesMenu(client, entity);
		}

		return;
	}

	if (CZone[client].SetName)
	{
		g_kvConfig.Rewind();

		if (g_kvConfig.JumpToKey(sArgs))
		{
			g_kvConfig.Rewind();
			CPrintToChat(client, "Zone name already exists, please pick a different name.");
			CZone[client].SetName = false;
			OpenCreateZonesMenu(client);
			return;
		}
		
		strcopy(CZone[client].Name, MAX_ZONE_NAME_LENGTH, sArgs);
		CZone[client].SetName = false;
		OpenCreateZonesMenu(client);
	}
	else if (g_bEffectKeyValue[client])
	{
		g_bEffectKeyValue[client] = false;

		char sValue[MAX_KEY_VALUE_LENGTH];
		strcopy(sValue, sizeof(sValue), sArgs);

		UpdateZoneEffectKey(g_iEffectKeyValue_Entity[client], g_sEffectKeyValue_Effect[client], g_sEffectKeyValue_EffectKey[client], sValue);

		char sName[MAX_ZONE_NAME_LENGTH];
		GetEntPropString(g_iEffectKeyValue_Entity[client], Prop_Data, "m_iName", sName, sizeof(sName));

		CPrintToChat(client, "Effect '%s' key '%s' for zone '%s' has been successfully updated to '%s'.", g_sEffectKeyValue_Effect[client], g_sEffectKeyValue_EffectKey[client], sName, sValue);

		ListZoneEffectKeys(client, g_iEffectKeyValue_Entity[client], g_sEffectKeyValue_Effect[client]);
	}

	if (g_iEditingName[client] != INVALID_ENT_REFERENCE)
	{
		int entity = EntRefToEntIndex(g_iEditingName[client]);

		char sName[MAX_ZONE_NAME_LENGTH];
		GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

		UpdateZonesSectionName(entity, sArgs);
		CPrintToChat(client, "Zone '%s' has been renamed successfully to '%s'.", sName, sArgs);
		g_iEditingName[client] = INVALID_ENT_REFERENCE;

		OpenZonePropertiesMenu(client, entity);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (client == 0 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	if (IsPlayerAlive(client))
	{
		float vecPosition[3];
		GetClientAbsOrigin(client, vecPosition);

		float vecOrigin[3];

		for (int i = 0; i < g_aZoneEntities.Length; i++)
		{
			int zone = EntRefToEntIndex(g_aZoneEntities.Get(i));

			if (IsValidEntity(zone))
			{
				switch (GetZoneTypeByIndex(zone))
				{
					case ZONE_TYPE_CIRCLE:
					{
						GetEntPropVector(zone, Prop_Data, "m_vecOrigin", vecOrigin);
						float distance = GetVectorDistance(vecOrigin, vecPosition);

						if (distance <= (Zone[zone].Radius / 2.0))
						{
							Action action = IsNearExternalZone(client, zone, ZONE_TYPE_CIRCLE);

							if (action <= Plugin_Changed)
							{
								IsNearExternalZone_Post(client, zone, ZONE_TYPE_CIRCLE);
							}
						}
						else
						{
							Action action = IsNotNearExternalZone(client, zone, ZONE_TYPE_CIRCLE);

							if (action <= Plugin_Changed)
							{
								IsNotNearExternalZone_Post(client, zone, ZONE_TYPE_CIRCLE);
							}
						}
					}

					case ZONE_TYPE_POLY:
					{
						float origin[3];
						origin[0] = vecPosition[0];
						origin[1] = vecPosition[1];
						origin[2] = vecPosition[2];

						origin[2] += 42.5;

						static float offset = 16.5;
						float clientpoints[4][3];

						clientpoints[0] = origin;
						clientpoints[0][0] -= offset;
						clientpoints[0][1] -= offset;

						clientpoints[1] = origin;
						clientpoints[1][0] += offset;
						clientpoints[1][1] -= offset;

						clientpoints[2] = origin;
						clientpoints[2][0] -= offset;
						clientpoints[2][1] += offset;

						clientpoints[3] = origin;
						clientpoints[3][0] += offset;
						clientpoints[3][1] += offset;

						bool IsInZone;
						for (int x = 0; x < 4; x++)
						{
							if (IsPointInZone(clientpoints[x], zone))
							{
								IsInZone = true;
								break;
							}
						}

						if (IsInZone)
						{
							Action action = IsNearExternalZone(client, zone, ZONE_TYPE_POLY);

							if (action <= Plugin_Changed)
							{
								IsNearExternalZone_Post(client, zone, ZONE_TYPE_POLY);
							}
						}
						else
						{
							Action action = IsNotNearExternalZone(client, zone, ZONE_TYPE_POLY);

							if (action <= Plugin_Changed)
							{
								IsNotNearExternalZone_Post(client, zone, ZONE_TYPE_POLY);
							}
						}
					}
				}
			}
		}
	}

	return Plugin_Continue;
}

public Action Command_EditZoneMenu(int client, int args)
{
	if (client == 0)
	{
		CReplyToCommand(client, "You must be in-game to use this command.");
		return Plugin_Handled;
	}

	FindZoneToEdit(client);
	return Plugin_Handled;
}

public Action Command_OpenZonesMenu(int client, int args)
{
	if (client == 0)
	{
		CReplyToCommand(client, "You must be in-game to use this command.");
		return Plugin_Handled;
	}

	OpenZonesMenu(client);
	return Plugin_Handled;
}

public Action Command_TeleportToZone(int client, int args)
{
	char sArg1[65];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sArg2[65];
	GetCmdArg(2, sArg2, sizeof(sArg2));

	switch (args)
	{
		case 0:
		{
			OpenTeleportToZoneMenu(client);
			return Plugin_Handled;
		}
		case 1:
		{
			char sCommand[64];
			GetCmdArg(0, sCommand, sizeof(sCommand));

			ReplyToCommand(client, "[SM] Usage: %s <#userid|name> <zone>", sCommand);
			return Plugin_Handled;
		}
	}

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS];
	bool tn_is_ml;

	int target_count = target_count = ProcessTargetString(sArg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_ALIVE, target_name, sizeof(target_name), tn_is_ml);

	if (target_count <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		TeleportToZone(client, sArg2);
	}

	return Plugin_Handled;
}

public Action Command_RegenerateZones(int client, int args)
{
	RegenerateZones(client);
	return Plugin_Handled;
}

public Action Command_DeleteAllZones(int client, int args)
{
	DeleteAllZones(client);
	return Plugin_Handled;
}

public Action Command_ReloadEffects(int client, int args)
{
	QueueEffects();
	CReplyToCommand(client, "Effects data has been reloaded.");
	return Plugin_Handled;
}

void FindZoneToEdit(int client)
{
	int entity = GetEarliestTouchZone(client);

	if (entity == -1 || !IsValidEntity(entity))
	{
		CPrintToChat(client, "Error: You are not currently standing in a zone to edit.");
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	OpenEditZoneMenu(client, entity);
}

int GetEarliestTouchZone(int client)
{
	for (int i = 0; i < g_aZoneEntities.Length; i++)
	{
		int zone = EntRefToEntIndex(g_aZoneEntities.Get(i));

		if (IsValidEntity(zone) && g_bIsInZone[client][zone])
		{
			return zone;
		}
	}

	return -1;
}

void OpenZonesMenu(int client)
{
	Menu menu = new Menu(MenuHandle_ZonesMenu);
	menu.SetTitle("Zones Manager");

	menu.AddItem("create", "Create Zones");
	menu.AddItem("manage", "Manage Zones\n ");
	AddMenuItemFormat(menu, "regenerate", ITEMDRAW_DEFAULT, "Regenerate Zones");
	AddMenuItemFormat(menu, "deleteall", ITEMDRAW_DEFAULT, "Delete all Zones");

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ZonesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "manage"))
			{
				OpenManageZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "create"))
			{
				OpenCreateZonesMenu(param1, true);
			}
			else if (StrEqual(sInfo, "regenerate"))
			{
				RegenerateZones(param1);
				OpenZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "deleteall"))
			{
				DeleteAllZones(param1);
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenTeleportToZoneMenu(int client)
{
	Menu menu = new Menu(MenuHandle_TeleportToZoneMenu);
	menu.SetTitle("Teleport to which zone:");

	for (int i = 0; i < g_aZoneEntities.Length; i++)
	{
		int zone = EntRefToEntIndex(g_aZoneEntities.Get(i));

		if (IsValidEntity(zone))
		{
			char sEntity[12];
			IntToString(zone, sEntity, sizeof(sEntity));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(zone, Prop_Data, "m_iName", sName, sizeof(sName));

			menu.AddItem(sEntity, sName);
		}
	}

	if (menu.ItemCount == 0)
	{
		menu.AddItem("", "[No Zones]", ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_TeleportToZoneMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEntity[64]; char sName[MAX_ZONE_NAME_LENGTH];
			menu.GetItem(param2, sEntity, sizeof(sEntity), _, sName, sizeof(sName));

			TeleportToZone(param1, sName);
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void RegenerateZones(int client = -1)
{
	if (g_iRegenerationTime > 0 && GetTime() < (g_iRegenerationTime + g_cRegenerateSpam.IntValue))
	{
		if (IsClientValid(client))
		{
			CReplyToCommand(client, "Spam Protection active, you can not regenerate the zones yet.");
		}
		else
		{
			PrintToServer("Spam Protection active, you can not regenerate the zones yet.");
		}
		
		return;
	}

	g_iRegenerationTime = GetTime();

	ClearAllZones();
	SpawnAllZones();

	if (IsClientValid(client))
	{
		CReplyToCommand(client, "All zones have been regenerated on the map.");
	}
}

void DeleteAllZones(int client = -1, bool confirmation = true)
{
	if (!IsClientValid(client))
	{
		ClearAllZones();
		ReparseMapZonesConfig(true);
		return;
	}

	if (!confirmation)
	{
		ClearAllZones();
		ReparseMapZonesConfig(true);
		CReplyToCommand(client, "All zones have been deleted from the map.");
		return;
	}

	Menu menu = new Menu(MenuHandle_ConfirmDeleteAllZones);
	menu.SetTitle("Are you sure you want to delete all zones on this map?");

	menu.AddItem("No", "No");
	menu.AddItem("Yes", "Yes");

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ConfirmDeleteAllZones(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "No"))
			{
				OpenZonesMenu(param1);
				return;
			}

			DeleteAllZones(param1, false);
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenManageZonesMenu(int client)
{
	Menu menu = new Menu(MenuHandle_ManageZonesMenu);
	menu.SetTitle("Manage Zones:");

	for (int i = 0; i < g_aZoneEntities.Length; i++)
	{
		int zone = EntRefToEntIndex(g_aZoneEntities.Get(i));

		if (IsValidEntity(zone))
		{
			char sEntity[12];
			IntToString(zone, sEntity, sizeof(sEntity));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(zone, Prop_Data, "m_iName", sName, sizeof(sName));

			menu.AddItem(sEntity, sName);
		}
	}

	if (menu.ItemCount == 0)
	{
		menu.AddItem("", "[No Zones]", ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ManageZonesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEntity[12]; char sName[MAX_ZONE_NAME_LENGTH];
			menu.GetItem(param2, sEntity, sizeof(sEntity), _, sName, sizeof(sName));

			OpenEditZoneMenu(param1, StringToInt(sEntity));
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenEditZoneMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandle_ManageEditMenu);
	menu.SetTitle("Manage Zone '%s':", sName);

	menu.AddItem("edit", "Edit Zone");
	menu.AddItem("delete", "Delete Zone\n ");
	menu.AddItem("effects_add", "Add Effect");

	int draw = ITEMDRAW_DISABLED;
	for (int i = 0; i < g_aEffectsList.Length; i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		g_aEffectsList.GetString(i, sEffect, sizeof(sEffect));

		// Debug Start
		StringMap temp = null;
		Zone[entity].Effects.GetValue(sEffect, temp);

		StringMapSnapshot snap1 = Zone[entity].Effects.Snapshot();
		char sKey[128];
		for (int j = 0; j < snap1.Length; j++)
		{
			snap1.GetKey(j, sKey, sizeof(sKey));
			PrintToChat(client, "Zone: %s, Effect (Index: %d): %s", sName, j, sKey);

			if (temp != null)
			{
				StringMapSnapshot snap2 = temp.Snapshot();
				for (int x = 0; x < snap2.Length; x++)
				{
					snap2.GetKey(x, sKey, sizeof(sKey));

					char sValue[MAX_KEY_VALUE_LENGTH];
					temp.GetString(sKey, sValue, sizeof(sValue));
					
					PrintToChat(client, "Key (Index: %d): %s, Value: %s", x, sKey, sValue);
				}
				delete snap2;
			}
		}

		delete snap1;
		// Debug End

		StringMap values = null;
		if (Zone[entity].Effects.GetValue(sEffect, values) && values != null)
		{
			draw = ITEMDRAW_DEFAULT;
			break;
		}
	}

	menu.AddItem("effects_edit", "Edit Effect", draw);
	menu.AddItem("effects_remove", "Remove Effect", draw);

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ManageEditMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");

			if (StrEqual(sInfo, "edit"))
			{
				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "delete"))
			{
				DisplayConfirmDeleteZoneMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "effects_add"))
			{
				if (!AddZoneEffectMenu(param1, entity))
				{
					OpenEditZoneMenu(param1, entity);
				}
			}
			else if (StrEqual(sInfo, "effects_edit"))
			{
				if (!EditZoneEffectMenu(param1, entity))
				{
					OpenEditZoneMenu(param1, entity);
				}
			}
			else if (StrEqual(sInfo, "effects_remove"))
			{
				if (!RemoveZoneEffectMenu(param1, entity))
				{
					OpenEditZoneMenu(param1, entity);
				}
			}
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenManageZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenZonePropertiesMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	char sRadiusAmount[64];
	FormatEx(sRadiusAmount, sizeof(sRadiusAmount), "\nRadius is currently: %.2f", Zone[entity].Radius);

	Menu menu = new Menu(MenuHandle_ZonePropertiesMenu);
	menu.SetTitle("Edit properties for zone '%s':%s", sName, GetZoneTypeByIndex(entity) == ZONE_TYPE_CIRCLE ? sRadiusAmount : "");

	menu.AddItem("edit_name", "Name");
	menu.AddItem("edit_type", "Type");
	menu.AddItem("edit_color", "Color");
	// TODO: Add new options from recently added create zone opens

	switch (GetZoneTypeByIndex(entity))
	{
		case ZONE_TYPE_BOX:
		{
			menu.AddItem("edit_startpoint_a", "StartPoint A");
			menu.AddItem("edit_startpoint_a_precision", "StartPoint A Precision");
			menu.AddItem("edit_startpoint_b", "StartPoint B");
			menu.AddItem("edit_startpoint_b_precision", "StartPoint B Precision");
		}

		case ZONE_TYPE_CIRCLE:
		{
			menu.AddItem("edit_startpoint", "StartPoint");
			menu.AddItem("edit_add_radius", "Radius +");
			menu.AddItem("edit_remove_radius", "Radius -");
		}

		case ZONE_TYPE_POLY:
		{
			menu.AddItem("edit_add_point", "Add a Point");
			menu.AddItem("edit_remove_point", "Remove last Point");
			menu.AddItem("edit_clear_points", "Clear all Points");
		}
	}

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ZonePropertiesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			if (StrEqual(sInfo, "edit_name"))
			{
				g_iEditingName[param1] = EntIndexToEntRef(entity);
				CPrintToChat(param1, "Type the new name for the zone '%s' in chat. Type \"!cancel\" to cancel this process.", sName);
			}
			else if (StrEqual(sInfo, "edit_type"))
			{
				OpenEditZoneTypeMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_color"))
			{
				OpenEditZoneColorMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_startpoint_a"))
			{
				float vecLook[3];
				GetClientLookPoint(param1, vecLook);

				UpdateZonesConfigKeyVector(entity, "start", vecLook);

				entity = RemakeZoneEntity(entity);

				OpenZonePropertiesMenu(param1, entity);

				//TODO: Make this work

				/*float start[3];
				GetClientLookPoint(param1, start, true);

				float end[3];
				//GetEntPropVector(entity, Prop_Data, "m_vecMaxs", end);
				GetZonesVectorData(entity, "end", end);

				float fMiddle[3];
				GetMiddleOfABox(start, end, fMiddle);

				TeleportEntity(entity, fMiddle, NULL_VECTOR, NULL_VECTOR);

				// Have the mins always be negative
				start[0] = start[0] - fMiddle[0];
				if(start[0] > 0.0)
				start[0] *= -1.0;
				start[1] = start[1] - fMiddle[1];
				if(start[1] > 0.0)
				start[1] *= -1.0;
				start[2] = start[2] - fMiddle[2];
				if(start[2] > 0.0)
				start[2] *= -1.0;

				SetEntPropVector(entity, Prop_Data, "m_vecMins", start);*/
			}
			else if (StrEqual(sInfo, "edit_startpoint_b"))
			{
				float vecLook[3];
				GetClientLookPoint(param1, vecLook);

				UpdateZonesConfigKeyVector(entity, "end", vecLook);

				entity = RemakeZoneEntity(entity);

				OpenZonePropertiesMenu(param1, entity);

				//TODO: Make this work

				/*float start[3];
				//GetEntPropVector(entity, Prop_Data, "m_vecMins", start);
				GetZonesVectorData(entity, "start", start);

				float end[3];
				GetClientLookPoint(param1, end, true);

				float fMiddle[3];
				GetMiddleOfABox(start, end, fMiddle);

				TeleportEntity(entity, fMiddle, NULL_VECTOR, NULL_VECTOR);

				// And the maxs always be positive
				end[0] = end[0] - fMiddle[0];
				if(end[0] < 0.0)
				end[0] *= -1.0;
				end[1] = end[1] - fMiddle[1];
				if(end[1] < 0.0)
				end[1] *= -1.0;
				end[2] = end[2] - fMiddle[2];
				if(end[2] < 0.0)
				end[2] *= -1.0;

				SetEntPropVector(entity, Prop_Data, "m_vecMaxs", end);*/

				//UpdateZonesConfigKeyVector(entity, "end", end);
			}
			else if (StrEqual(sInfo, "edit_startpoint_a_precision"))
			{
				OpenEditZoneStartPointAMenu(param1, entity, true);
			}
			else if (StrEqual(sInfo, "edit_startpoint_b_precision"))
			{
				OpenEditZoneStartPointAMenu(param1, entity, false);
			}
			else if (StrEqual(sInfo, "edit_startpoint"))
			{
				float start[3];
				GetClientLookPoint(param1, start);

				TeleportEntity(entity, start, NULL_VECTOR, NULL_VECTOR);

				UpdateZonesConfigKeyVector(entity, "start", start);
				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_add_radius"))
			{
				Zone[entity].Radius += 5.0;
				Zone[entity].Radius = ClampCell(Zone[entity].Radius, 0.0, 430.0);

				char sValue[64];
				FloatToString(Zone[entity].Radius, sValue, sizeof(sValue));
				UpdateZonesConfigKey(entity, "radius", sValue);

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_remove_radius"))
			{
				Zone[entity].Radius -= 5.0;
				Zone[entity].Radius = ClampCell(Zone[entity].Radius, 0.0, 430.0);

				char sValue[64];
				FloatToString(Zone[entity].Radius, sValue, sizeof(sValue));
				UpdateZonesConfigKey(entity, "radius", sValue);

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_add_point"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);

				Zone[entity].PointsData.PushArray(vLookPoint, 3);

				SaveZonePointsData(entity);

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_remove_point"))
			{
				int size = Zone[entity].PointsData.Length;
				int actual = size - 1;

				if (size > 0)
				{
					Zone[entity].PointsData.Resize(actual);
					SaveZonePointsData(entity);
				}

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_clear_points"))
			{
				Zone[entity].PointsData.Clear();
				SaveZonePointsData(entity);

				OpenZonePropertiesMenu(param1, entity);
			}
			else
			{
				OpenZonePropertiesMenu(param1, entity);
			}
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenEditZoneStartPointAMenu(int client, int entity, bool whichpoint)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandle_ZoneEditStartPointMenu);
	menu.SetTitle("Edit start point %s properties for zone '%s':", whichpoint ? "A" : "B", sName);

	if (whichpoint)
	{
		menu.AddItem("a_add_x", "X +");
		menu.AddItem("a_remove_x", "X -");
		menu.AddItem("a_add_y", "Y +");
		menu.AddItem("a_remove_y", "Y -");
		menu.AddItem("a_add_z", "Z +");
		menu.AddItem("a_remove_z", "Z -");
	}
	else
	{
		menu.AddItem("b_add_x", "X +");
		menu.AddItem("b_remove_x", "X -");
		menu.AddItem("b_add_y", "Y +");
		menu.AddItem("b_remove_y", "Y -");
		menu.AddItem("b_add_z", "Z +");
		menu.AddItem("b_remove_z", "Z -");
	}

	PushMenuCell(menu, "entity", entity);
	PushMenuCell(menu, "whichpoint", whichpoint);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ZoneEditStartPointMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");
			bool whichpoint = view_as<bool>(GetMenuCell(menu, "whichpoint"));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			float precision = g_cPrecisionValue.FloatValue;

			if (StrEqual(sInfo, "a_add_x"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[0] += precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_add_y"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[1] += precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_add_z"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[2] += precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_remove_x"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[0] -= precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_remove_y"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[1] -= precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_remove_z"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[2] -= precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "b_add_x"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[0] += precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_add_y"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[1] += precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_add_z"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[2] += precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_remove_x"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[0] -= precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_remove_y"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[1] -= precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_remove_z"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[2] -= precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else
			{
				OpenZonePropertiesMenu(param1, entity);
			}

			entity = RemakeZoneEntity(entity);

			OpenEditZoneStartPointAMenu(param1, entity, whichpoint);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenZonePropertiesMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

int RemakeZoneEntity(int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	DeleteZone(entity);
	return SpawnAZone(sName);
}

void GetZonesVectorData(int entity, const char[] name, float[3] vecdata)
{
	if (g_kvConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	g_kvConfig.Rewind();

	if (g_kvConfig.JumpToKey(sName))
	{
		g_kvConfig.GetVector(name, vecdata);
		g_kvConfig.Rewind();
	}
}

void UpdateZonesSectionName(int entity, const char[] name)
{
	if (g_kvConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	g_kvConfig.Rewind();

	if (g_kvConfig.JumpToKey(sName))
	{
		g_kvConfig.SetSectionName(name);
		g_kvConfig.Rewind();
	}

	SaveMapConfig();

	SetEntPropString(entity, Prop_Data, "m_iName", name);
}

void UpdateZonesConfigKey(int entity, const char[] key, const char[] value)
{
	if (g_kvConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	g_kvConfig.Rewind();

	if (g_kvConfig.JumpToKey(sName))
	{
		g_kvConfig.SetString(key, value);
		g_kvConfig.Rewind();
	}

	SaveMapConfig();
}

void UpdateZonesConfigKeyVector(int entity, const char[] key, float[3] value)
{
	if (g_kvConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	g_kvConfig.Rewind();

	if (g_kvConfig.JumpToKey(sName))
	{
		g_kvConfig.SetVector(key, value);
		g_kvConfig.Rewind();
	}

	SaveMapConfig();
}

void SaveZonePointsData(int entity)
{
	if (g_kvConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	g_kvConfig.Rewind();

	if (g_kvConfig.JumpToKey(sName))
	{
		g_kvConfig.DeleteKey("points");

		if (g_kvConfig.JumpToKey("points", true))
		{
			for (int i = 0; i < Zone[entity].PointsData.Length; i++)
			{
				char sID[12];
				IntToString(i, sID, sizeof(sID));

				float coordinates[3];
				Zone[entity].PointsData.GetArray(i, coordinates, sizeof(coordinates));

				g_kvConfig.SetVector(sID, coordinates);
			}
		}

		g_kvConfig.Rewind();
	}

	SaveMapConfig();
}

void OpenEditZoneTypeMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	char sAddendum[256];
	FormatEx(sAddendum, sizeof(sAddendum), " for %s", sName);

	Menu menu = new Menu(MenuHandler_EditZoneTypeMenu);
	menu.SetTitle("Choose a new zone type%s:", sAddendum);

	for (int i = 0; i < ZONE_TYPES; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));

		char sType[MAX_ZONE_TYPE_LENGTH];
		GetZoneNameByType(i, sType, sizeof(sType));

		menu.AddItem(sID, sType);
	}

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_EditZoneTypeMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12]; char sType[MAX_ZONE_TYPE_LENGTH];
			menu.GetItem(param2, sID, sizeof(sID), _, sType, sizeof(sType));
			//int type = StringToInt(sID);

			int entity = GetMenuCell(menu, "entity");

			UpdateZonesConfigKey(entity, "type", sType);

			entity = RemakeZoneEntity(entity);

			OpenZonePropertiesMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenEditZoneColorMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	char sAddendum[256];
	FormatEx(sAddendum, sizeof(sAddendum), " for %s", sName);

	Menu menu = new Menu(MenuHandler_EditZoneColorMenu);
	menu.SetTitle("Choose a new zone color%s:", sAddendum);

	for (int i = 0; i < g_aColors.Length; i++)
	{
		char sColor[64];
		g_aColors.GetString(i, sColor, sizeof(sColor));

		int colors[4];
		g_smColorData.GetArray(sColor, colors, sizeof(colors));

		char sVector[64];
		FormatEx(sVector, sizeof(sVector), "%i %i %i %i", colors[0], colors[1], colors[2], colors[3]);

		menu.AddItem(sVector, sColor);
	}

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_EditZoneColorMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sVector[64]; char sColor[64];
			menu.GetItem(param2, sVector, sizeof(sVector), _, sColor, sizeof(sColor));

			int entity = GetMenuCell(menu, "entity");

			UpdateZonesConfigKey(entity, "color", sVector);

			int color[4];
			g_smColorData.GetArray(sColor, color, sizeof(color));
			Zone[entity].Color = color;

			OpenEditZoneColorMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void DisplayConfirmDeleteZoneMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandle_ManageConfirmDeleteZoneMenu);
	menu.SetTitle("Are you sure you want to delete '%s':", sName);

	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_ManageConfirmDeleteZoneMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");

			if (StrEqual(sInfo, "no"))
			{
				OpenEditZoneMenu(param1, entity);
				return;
			}

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			DeleteZone(entity, true);
			CPrintToChat(param1, "You have deleted the zone '%s'.", sName);

			OpenManageZonesMenu(param1);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenCreateZonesMenu(int client, bool reset = false)
{
	if (reset)
	{
		ResetCreateZoneVariables(client);
	}

	if (CZone[client].Type == ZONE_TYPE_POLY && CZone[client].PointsData == null)
	{
		CZone[client].PointsData = new ArrayList(3);
	}
	else if (CZone[client].Type != ZONE_TYPE_POLY)
	{
		delete CZone[client].PointsData;
	}

	bool bValidPoints = false;

	if (CZone[client].Type == ZONE_TYPE_POLY && CZone[client].PointsData != null)
	{
		if (CZone[client].PointsData.Length > 2)
		{
			bValidPoints = true;
		}
	}
	else if (CZone[client].Type == ZONE_TYPE_BOX)
	{
		if (!IsPositionNull(CZone[client].Start) && !IsPositionNull(CZone[client].End))
		{
			bValidPoints = true;
		}
	}
	else if (CZone[client].Type == ZONE_TYPE_CIRCLE)
	{
		if (!IsPositionNull(CZone[client].Start))
		{
			bValidPoints = true;
		}
	}

	char sType[MAX_ZONE_TYPE_LENGTH];
	GetZoneNameByType(CZone[client].Type, sType, sizeof(sType));

	Menu menu = new Menu(MenuHandle_CreateZonesMenu);
	menu.SetTitle("Create a Zone:");

	menu.AddItem("create", "Create Zone\n ", (bValidPoints && CZone[client].Type > ZONE_TYPE_NONE && strlen(CZone[client].Name) > 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	char sBuffer[256];
	if (CZone[client].Type == ZONE_TYPE_POLY)
	{
		Format(sBuffer, sizeof(sBuffer), "Points: %d", CZone[client].PointsData.Length);
	}

	AddMenuItemFormat(menu, "name", ITEMDRAW_DEFAULT, "Name: %s", strlen(CZone[client].Name) > 0 ? CZone[client].Name : "N/A");
	AddMenuItemFormat(menu, "type", ITEMDRAW_DEFAULT, "Type: %s\n \n%s", sType, sBuffer);

	switch (CZone[client].Type)
	{
		case ZONE_TYPE_BOX:
		{
			menu.AddItem("start", "Set Starting Point", ITEMDRAW_DEFAULT);
			menu.AddItem("end", "Set Ending Point", ITEMDRAW_DEFAULT);
		}

		case ZONE_TYPE_CIRCLE:
		{
			menu.AddItem("start", "Set Center Point", ITEMDRAW_DEFAULT);
			AddMenuItemFormat(menu, "add_radius", ITEMDRAW_DEFAULT, "Radius +%.1f: %.1f", g_cPrecisionValue.FloatValue, CZone[client].Radius);
			AddMenuItemFormat(menu, "rem_radius", ITEMDRAW_DEFAULT, "Radius -%.1f: %.1f", g_cPrecisionValue.FloatValue, CZone[client].Radius);
			// TODO: Add cvar for default radius
			// TODO: Add customizable points height
		}

		case ZONE_TYPE_POLY:
		{
			menu.AddItem("add", "Add Zone Point", ITEMDRAW_DEFAULT);
			menu.AddItem("remove", "Remove Last Point", ITEMDRAW_DEFAULT);
			menu.AddItem("clear", "Clear All Points", ITEMDRAW_DEFAULT);
			// TODO: Add customizable points height
		}
	}

	AddMenuItemFormat(menu, "color", ITEMDRAW_DEFAULT, "Color: %s", (strlen(CZone[client].Color) > 0) ? CZone[client].Color : "Pink");
	AddMenuItemFormat(menu, "view", ITEMDRAW_DEFAULT, "Display: %s", CZone[client].Display ? "Yes" : "No");
	// AddMenuItemFormat(menu, "draw", ITEMDRAW_DEFAULT, "Draw whole zone: %s", CZone[client].DrawWholeZone ? "Yes" : "No");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandle_CreateZonesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "name"))
			{
				CZone[param1].SetName = true;
				CPrintToChat(param1, "Type the name of this new zone in chat. Type \"!cancel\" to cancel this process.");
			}
			else if (StrEqual(sInfo, "type"))
			{
				CZone[param1].Type++;

				if (CZone[param1].Type > ZONE_TYPES)
				{
					CZone[param1].Type = ZONE_TYPE_BOX;
				}

				OpenZoneTypeMenu(param1);
			}
			else if (StrEqual(sInfo, "start"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);
				Array_Copy(vLookPoint, CZone[param1].Start, 3);
				CPrintToChat(param1, "Starting point: %.2f/%.2f/%.2f", CZone[param1].Start[0], CZone[param1].Start[1], CZone[param1].Start[2]);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "end"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);
				Array_Copy(vLookPoint, CZone[param1].End, 3);
				CPrintToChat(param1, "Ending point: %.2f/%.2f/%.2f", CZone[param1].End[0], CZone[param1].End[1], CZone[param1].End[2]);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "add_radius"))
			{
				CZone[param1].Radius += g_cPrecisionValue.FloatValue;
				ClampCell(CZone[param1].Radius, 0.0, 430.0);
				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "rem_radius"))
			{
				CZone[param1].Radius -= g_cPrecisionValue.FloatValue;
				ClampCell(CZone[param1].Radius, 0.0, 430.0);
				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "add"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);

				CZone[param1].PointsData.PushArray(vLookPoint, 3);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "remove"))
			{
				int size = CZone[param1].PointsData.Length;

				if (size > 0)
				{
					CZone[param1].PointsData.Erase(size-1);
				}

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "clear"))
			{
				CZone[param1].PointsData.Clear();

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "color"))
			{
				OpenZonesColorMenu(param1);
			}
			else if (StrEqual(sInfo, "view"))
			{
				CZone[param1].Display = !CZone[param1].Display;
				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "create"))
			{
				CreateNewZone(param1);
				OpenZonesMenu(param1);
			}
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				ResetCreateZoneVariables(param1);
				OpenZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

bool AddZoneEffectMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandler_AddZoneEffect);
	menu.SetTitle("Add a zone effect to %s:", sName);

	for (int i = 0; i < g_aEffectsList.Length; i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		g_aEffectsList.GetString(i, sEffect, sizeof(sEffect));

		int draw = ITEMDRAW_DEFAULT;

		StringMap values = null;
		if (Zone[entity].Effects.GetValue(sEffect, values) && values != null)
		{
			draw = ITEMDRAW_DISABLED;
		}

		menu.AddItem(sEffect, sEffect, draw);
	}

	if (menu.ItemCount == 0)
	{
		menu.AddItem("", "[No Effects]", ITEMDRAW_DISABLED);
	}

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return true;
}

public int MenuHandler_AddZoneEffect(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			menu.GetItem(param2, sEffect, sizeof(sEffect));

			int entity = GetMenuCell(menu, "entity");

			AddEffectToZone(entity, sEffect);

			OpenEditZoneMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

bool EditZoneEffectMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandler_EditZoneEffect);
	menu.SetTitle("Pick a zone effect to edit for %s:", sName);

	for (int i = 0; i < g_aEffectsList.Length; i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		g_aEffectsList.GetString(i, sEffect, sizeof(sEffect));

		StringMap values = null;
		if (Zone[entity].Effects.GetValue(sEffect, values) && values != null)
		{
			menu.AddItem(sEffect, sEffect);
		}
	}

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return true;
}

public int MenuHandler_EditZoneEffect(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			menu.GetItem(param2, sEffect, sizeof(sEffect));

			int entity = GetMenuCell(menu, "entity");

			ListZoneEffectKeys(param1, entity, sEffect);

			// OpenEditZoneMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

bool ListZoneEffectKeys(int client, int entity, const char[] effect)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandler_EditZoneEffectKeyVaue);
	menu.SetTitle("Pick effect key to edit for %s:", sName);

	StringMap smEffects = null;
	Zone[entity].Effects.GetValue(effect, smEffects);

	if (smEffects != null)
	{
		StringMapSnapshot keys = smEffects.Snapshot();
		for (int i = 0; i < keys.Length; i++)
		{
			char sKey[MAX_KEY_NAME_LENGTH];
			keys.GetKey(i, sKey, sizeof(sKey));

			char sValue[MAX_KEY_VALUE_LENGTH];
			smEffects.GetString(sKey, sValue, sizeof(sValue));
			
			AddMenuItemFormat(menu, sKey, ITEMDRAW_DEFAULT, "%s\nValue: %s", sKey, sValue);
		}
		delete keys;

		if (menu.ItemCount == 0)
		{
			delete menu;
			return false;
		}
	}
	else
	{
		delete menu;
		return false;
	}

	PushMenuCell(menu, "entity", entity);
	PushMenuString(menu, "effect", effect);

	g_iEffectKeyValue_Entity[client] = -1;
	g_sEffectKeyValue_Effect[client][0] = '\0';
	g_sEffectKeyValue_EffectKey[client][0] = '\0';

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return true;
}

public int MenuHandler_EditZoneEffectKeyVaue(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			g_iEffectKeyValue_Entity[param1] = GetMenuCell(menu, "entity");
			GetMenuString(menu, "effect", g_sEffectKeyValue_Effect[param1], sizeof(g_sEffectKeyValue_Effect[]));
			menu.GetItem(param2, g_sEffectKeyValue_EffectKey[param1], sizeof(g_sEffectKeyValue_EffectKey[]));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(g_iEffectKeyValue_Entity[param1], Prop_Data, "m_iName", sName, sizeof(sName));

			g_bEffectKeyValue[param1] = true;

			CPrintToChat(param1, "Type the new value for the effect '%s' key '%s' on zone '%s' in chat. Type \"!cancel\" to cancel this process.", g_sEffectKeyValue_Effect[param1], g_sEffectKeyValue_EffectKey[param1], sName);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				EditZoneEffectMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void AddEffectToZone(int entity, const char[] effect)
{
	if (g_kvConfig == null)
	{
		return;
	}

	g_kvConfig.Rewind();

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	StringMap keys = null;
	g_smEffectKeys.GetValue(effect, keys);

	if (g_kvConfig.JumpToKey(sName) && g_kvConfig.JumpToKey("effects", true) && g_kvConfig.JumpToKey(effect, true))
	{
		if (keys != null)
		{
			Zone[entity].Effects.SetValue(effect, CloneHandle(keys));

			StringMapSnapshot map = keys.Snapshot();

			for (int i = 0; i < map.Length; i++)
			{
				char sKey[MAX_KEY_NAME_LENGTH];
				map.GetKey(i, sKey, sizeof(sKey));

				char sValue[MAX_KEY_VALUE_LENGTH];
				keys.GetString(sKey, sValue, sizeof(sValue));

				g_kvConfig.SetString(sKey, sValue);
			}

			delete map;
		}

		g_kvConfig.Rewind();
	}

	SaveMapConfig();
}

stock void UpdateZoneEffectKey(int entity, const char[] effect_name, const char[] key, char[] value)
{
	if (g_kvConfig == null)
	{
		return;
	}

	g_kvConfig.Rewind();

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (g_kvConfig.JumpToKey(sName) && g_kvConfig.JumpToKey("effects", true) && g_kvConfig.JumpToKey(effect_name, true))
	{
		if (strlen(value) == 0)
		{
			StringMap keys = null;
			g_smEffectKeys.GetValue(effect_name, keys);

			keys.GetString(key, value, MAX_KEY_VALUE_LENGTH);
		}

		g_kvConfig.SetString(key, value);
		g_kvConfig.Rewind();

		StringMap smEffects = null;
		Zone[entity].Effects.GetValue(effect_name, smEffects);

		StringMapSnapshot keys = smEffects.Snapshot();
		for (int i = 0; i < keys.Length; i++)
		{
			char sKey[MAX_KEY_NAME_LENGTH];
			keys.GetKey(i, sKey, sizeof(sKey));

			if (StrEqual(sKey, key, false))
			{
				smEffects.SetString(key, value);
			}
		}

		delete keys;
	}

	SaveMapConfig();
}

bool RemoveZoneEffectMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = new Menu(MenuHandler_RemoveZoneEffect);
	menu.SetTitle("Add a zone type to %s to remove:", sName);

	for (int i = 0; i < g_aEffectsList.Length; i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		g_aEffectsList.GetString(i, sEffect, sizeof(sEffect));

		int draw = ITEMDRAW_DEFAULT;

		StringMap values = null;
		if (!Zone[entity].Effects.GetValue(sEffect, values))
		{
			draw = ITEMDRAW_DISABLED;
		}

		menu.AddItem(sEffect, sEffect, draw);
	}

	PushMenuCell(menu, "entity", entity);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return true;
}

public int MenuHandler_RemoveZoneEffect(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			menu.GetItem(param2, sEffect, sizeof(sEffect));

			int entity = GetMenuCell(menu, "entity");

			RemoveEffectFromZone(entity, sEffect);

			OpenEditZoneMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void RemoveEffectFromZone(int entity, const char[] effect)
{
	if (g_kvConfig == null)
	{
		return;
	}

	g_kvConfig.Rewind();

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	StringMap values = null;
	if (Zone[entity].Effects.GetValue(effect, values))
	{
		delete values;
		Zone[entity].Effects.Remove(effect);
	}

	if (g_kvConfig.JumpToKey(sName) && g_kvConfig.JumpToKey("effects", true) && g_kvConfig.JumpToKey(effect))
	{
		g_kvConfig.DeleteThis();
		g_kvConfig.Rewind();
	}

	SaveMapConfig();
}

void OpenZoneTypeMenu(int client)
{
	char sAddendum[256];
	FormatEx(sAddendum, sizeof(sAddendum), " for %s", CZone[client].Name);

	Menu menu = new Menu(MenuHandler_ZoneTypeMenu);
	menu.SetTitle("Choose a zone type%s:", strlen(CZone[client].Name) > 0 ? sAddendum : "");

	for (int i = 0; i < ZONE_TYPES; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));

		char sType[MAX_ZONE_TYPE_LENGTH];
		GetZoneNameByType(i, sType, sizeof(sType));

		menu.AddItem(sID, sType);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ZoneTypeMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12]; char sType[MAX_ZONE_TYPE_LENGTH];
			menu.GetItem(param2, sID, sizeof(sID), _, sType, sizeof(sType));
			int type = StringToInt(sID);

			char sAddendum[256];
			FormatEx(sAddendum, sizeof(sAddendum), " for %s", CZone[param1].Name);

			CZone[param1].Type = type;
			CPrintToChat(param1, "Zone type%s set to %s.", sAddendum, sType);
			OpenCreateZonesMenu(param1);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenCreateZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void OpenZonesColorMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ZoneColorMenu);
	menu.SetTitle("Choose a color:");

	for (int i = 0; i < g_aColors.Length; i++)
	{
		char sColor[64];
		g_aColors.GetString(i, sColor, sizeof(sColor));
		menu.AddItem(sColor, sColor);
	}

	menu.ExitBackButton = true;
	menu.ExitButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ZoneColorMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			menu.GetItem(param2, CZone[param1].Color, sizeof(eCreateZone::Color));
			CPrintToChat(param1, "Zone color set to %s.", CZone[param1].Color);
			OpenCreateZonesMenu(param1);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenCreateZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void CreateNewZone(int client)
{
	if (strlen(CZone[client].Name) == 0)
	{
		CPrintToChat(client, "You must set a zone name in order to create it.");
		OpenCreateZonesMenu(client);
		return;
	}

	g_kvConfig.Rewind();

	if (g_kvConfig.JumpToKey(CZone[client].Name))
	{
		g_kvConfig.Rewind();
		CPrintToChat(client, "Zone already exists, please pick a different name.");
		OpenCreateZonesMenu(client);
		return;
	}

	g_kvConfig.JumpToKey(CZone[client].Name, true);

	char sType[MAX_ZONE_TYPE_LENGTH];
	GetZoneNameByType(CZone[client].Type, sType, sizeof(sType));
	g_kvConfig.SetString("type", sType);

	CZone[client].iColors[0] = 255;
	CZone[client].iColors[1] = 20;
	CZone[client].iColors[2] = 147;
	CZone[client].iColors[3] = 255;

	if (strlen(CZone[client].Color) > 0)
	{
		g_smColorData.GetArray(CZone[client].Color, CZone[client].iColors, sizeof(eCreateZone::iColors));
	}

	char sColor[64];
	FormatEx(sColor, sizeof(sColor), "%i %i %i %i", CZone[client].iColors[0], CZone[client].iColors[1], CZone[client].iColors[2], CZone[client].iColors[3]);
	g_kvConfig.SetString("color", sColor);

	#warning Make it configurable
	CZone[client].PointsHeight = g_cDefaultHeight.FloatValue; 

	switch (CZone[client].Type)
	{
		case ZONE_TYPE_BOX:
		{
			g_kvConfig.SetVector("start", CZone[client].Start);
			g_kvConfig.SetVector("end", CZone[client].End);
		}

		case ZONE_TYPE_CIRCLE:
		{
			g_kvConfig.SetVector("start", CZone[client].Start);
			g_kvConfig.SetFloat("radius", CZone[client].Radius);
		}

		case ZONE_TYPE_POLY:
		{
			g_kvConfig.SetFloat("points_height", CZone[client].PointsHeight);

			if (g_kvConfig.JumpToKey("points", true))
			{
				for (int i = 0; i < CZone[client].PointsData.Length; i++)
				{
					char sID[12];
					IntToString(i, sID, sizeof(sID));

					float coordinates[3];
					CZone[client].PointsData.GetArray(i, coordinates, sizeof(coordinates));
					g_kvConfig.SetVector(sID, coordinates);
				}
			}
		}
	}

	g_kvConfig.SetNum("display", CZone[client].Display);

	SaveMapConfig();

	CreateZone(CZone[client]);
	CPrintToChat(client, "Zone '%s' has been created successfully.", CZone[client].Name);
}

void ResetCreateZoneVariables(int client)
{
	CZone[client].Name[0] = '\0';
	CZone[client].Color[0] = '\0';
	CZone[client].Type = ZONE_TYPE_NONE;
	CZone[client].Start[0] = 0.0;
	CZone[client].Start[1] = 0.0;
	CZone[client].Start[2] = 0.0;
	CZone[client].End[0] = 0.0;
	CZone[client].End[1] = 0.0;
	CZone[client].End[2] = 0.0;
	CZone[client].Radius = 0.0;
	delete CZone[client].PointsData;
	CZone[client].PointsHeight = g_cDefaultHeight.FloatValue;
	CZone[client].SetName = false;
	CZone[client].Display = true;
}

void GetZoneNameByType(int type, char[] buffer, int size)
{
	switch (type)
	{
		case ZONE_TYPE_NONE: strcopy(buffer, size, "N/A");
		case ZONE_TYPE_BOX: strcopy(buffer, size, "Standard");
		case ZONE_TYPE_CIRCLE: strcopy(buffer, size, "Radius/Circle");
		case ZONE_TYPE_POLY: strcopy(buffer, size, "Polygons");
	}
}

int GetZoneTypeByIndex(int entity)
{
	char sClassname[64];
	GetEntityClassname(entity, sClassname, sizeof(sClassname));

	if (StrEqual(sClassname, "trigger_multiple"))
	{
		return ZONE_TYPE_BOX;
	}
	else if (StrEqual(sClassname, "info_target"))
	{
		return Zone[entity].PointsData != null ? ZONE_TYPE_POLY : ZONE_TYPE_CIRCLE;
	}

	return ZONE_TYPE_BOX;
}

int GetZoneTypeByName(const char[] sType)
{
	if (StrEqual(sType, "Standard"))
	{
		return ZONE_TYPE_BOX;
	}
	else if (StrEqual(sType, "Radius/Circle"))
	{
		return ZONE_TYPE_CIRCLE;
	}
	else if (StrEqual(sType, "Polygons"))
	{
		return ZONE_TYPE_POLY;
	}

	return ZONE_TYPE_BOX;
}

void SaveMapConfig()
{
	if (g_kvConfig == null)
	{
		return;
	}

	char sMap[32];
	GetCurrentMap(sMap, sizeof(sMap));

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/zones/%s.cfg", sMap);

	g_kvConfig.Rewind();
	KeyValuesToFile(g_kvConfig, sPath);
}

public Action Timer_DisplayZones(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		if (CZone[i].Display)
		{
			int iColor[4];

			iColor[0] = 255;
			iColor[1] = 20;
			iColor[2] = 147;
			iColor[3] = 255;

			if (strlen(CZone[i].Color) > 0)
			{
				g_smColorData.GetArray(CZone[i].Color, iColor, sizeof(iColor));
			}
			
			switch (CZone[i].Type)
			{
				case ZONE_TYPE_BOX:
				{
					if (!IsPositionNull(CZone[i].Start) && !IsPositionNull(CZone[i].End))
					{
						TE_DrawBeamBoxToClient(i, CZone[i].Start, CZone[i].End, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_ENDWIDTH, TE_FADELENGTH, TE_AMPLITUDE, iColor, TE_SPEED);
					}
				}

				case ZONE_TYPE_CIRCLE:
				{
					if (!IsPositionNull(CZone[i].Start))
					{
						TE_SetupBeamRingPointToClient(i, CZone[i].Start, CZone[i].Radius, CZone[i].Radius + 0.1, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_AMPLITUDE, iColor, TE_SPEED, TE_FLAGS);
					}
				}

				case ZONE_TYPE_POLY:
				{
					if (CZone[i].PointsData != null && CZone[i].PointsData.Length > 0)
					{
						for (int x = 0; x < CZone[i].PointsData.Length; x++)
						{
							float coordinates[3];
							CZone[i].PointsData.GetArray(x, coordinates, sizeof(coordinates));

							int index;

							if (x + 1 == CZone[i].PointsData.Length)
							{
								index = 0;
							}
							else
							{
								index = x + 1;
							}

							float nextpoint[3];
							CZone[i].PointsData.GetArray(index, nextpoint, sizeof(nextpoint));

							TE_SetupBeamPointsToClient(i, coordinates, nextpoint, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_ENDWIDTH, TE_FADELENGTH, TE_AMPLITUDE, iColor, TE_SPEED);
						}
					}
				}
			}
		}
	}

	float vecOrigin[3];
	float vecStart[3];
	float vecEnd[3];

	for (int x = 0; x < g_aZoneEntities.Length; x++)
	{
		int zone = EntRefToEntIndex(g_aZoneEntities.Get(x));

		if (IsValidEntity(zone))
		{
			GetEntPropVector(zone, Prop_Data, "m_vecOrigin", vecOrigin);

			switch (GetZoneTypeByIndex(zone))
			{
				case ZONE_TYPE_BOX:
				{
					GetAbsBoundingBox(zone, vecStart, vecEnd);
					TE_DrawBeamBoxToAll(vecStart, vecEnd, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_ENDWIDTH, TE_FADELENGTH, TE_AMPLITUDE, Zone[zone].Color, TE_SPEED);
				}

				case ZONE_TYPE_CIRCLE:
				{
					TE_SetupBeamRingPoint(vecOrigin, Zone[zone].Radius, Zone[zone].Radius + 0.1, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_AMPLITUDE, Zone[zone].Color, TE_SPEED, TE_FLAGS);
					TE_SendToAll();
				}

				case ZONE_TYPE_POLY:
				{
					if (Zone[zone].PointsData != null && Zone[zone].PointsData.Length > 0)
					{
						for (int y = 0; y < Zone[zone].PointsData.Length; y++)
						{
							float coordinates[3];
							Zone[zone].PointsData.GetArray(y, coordinates, sizeof(coordinates));

							int index;

							if (y + 1 == Zone[zone].PointsData.Length)
							{
								index = 0;
							}
							else
							{
								index = y + 1;
							}

							float nextpoint[3];
							Zone[zone].PointsData.GetArray(index, nextpoint, sizeof(nextpoint));

							TE_SetupBeamPoints(coordinates, nextpoint, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_ENDWIDTH, TE_FADELENGTH, TE_AMPLITUDE, Zone[zone].Color, TE_SPEED);
							TE_SendToAll();
						}
					}
				}
			}
		}
	}
}

void GetAbsBoundingBox(int ent, float mins[3], float maxs[3])
{
	float origin[3];

	GetEntPropVector(ent, Prop_Data, "m_vecOrigin", origin);
	GetEntPropVector(ent, Prop_Data, "m_vecMins", mins);
	GetEntPropVector(ent, Prop_Data, "m_vecMaxs", maxs);

	mins[0] += origin[0];
	mins[1] += origin[1];
	mins[2] += origin[2];

	maxs[0] += origin[0];
	maxs[1] += origin[1];
	maxs[2] += origin[2];
}

int CreateZone(eCreateZone Data)
{
	char sType[MAX_ZONE_TYPE_LENGTH];
	GetZoneNameByType(Data.Type, sType, sizeof(sType));

	LogMessage("Spawning Zone: %s - %s - %.2f/%.2f/%.2f - %.2f/%.2f/%.2f - %.2f", Data.Name, sType, Data.Start[0], Data.Start[1], Data.Start[2], Data.End[0], Data.End[1], Data.End[2], Data.Radius);

	int entity = -1;
	switch (Data.Type)
	{
		case ZONE_TYPE_BOX:
		{
			entity = CreateEntityByName("trigger_multiple");

			if (IsValidEntity(entity))
			{
				SetEntityModel(entity, ZONE_MODEL);

				DispatchKeyValue(entity, "targetname", Data.Name);
				DispatchKeyValue(entity, "spawnflags", "257");
				DispatchKeyValue(entity, "StartDisabled", "0");
				DispatchKeyValue(entity, "wait", "0");

				DispatchSpawn(entity);

				SetEntProp(entity, Prop_Send, "m_spawnflags", 257);
				SetEntProp(entity, Prop_Send, "m_nSolidType", 2);
				SetEntProp(entity, Prop_Send, "m_fEffects", 32);

				float fMiddle[3];
				GetMiddleOfABox(Data.Start, Data.End, fMiddle);
				TeleportEntity(entity, fMiddle, NULL_VECTOR, NULL_VECTOR);

				// Have the mins always be negative
				Data.Start[0] = Data.Start[0] - fMiddle[0];
				if(Data.Start[0] > 0.0)
					Data.Start[0] *= -1.0;
				Data.Start[1] = Data.Start[1] - fMiddle[1];
				if(Data.Start[1] > 0.0)
					Data.Start[1] *= -1.0;
				Data.Start[2] = Data.Start[2] - fMiddle[2];
				if(Data.Start[2] > 0.0)
					Data.Start[2] *= -1.0;

				// And the maxs always be positive
				Data.End[0] = Data.End[0] - fMiddle[0];
				if(Data.End[0] < 0.0)
					Data.End[0] *= -1.0;
				Data.End[1] = Data.End[1] - fMiddle[1];
				if(Data.End[1] < 0.0)
					Data.End[1] *= -1.0;
				Data.End[2] = Data.End[2] - fMiddle[2];
				if(Data.End[2] < 0.0)
					Data.End[2] *= -1.0;

				SetEntPropVector(entity, Prop_Data, "m_vecMins", Data.Start);
				SetEntPropVector(entity, Prop_Data, "m_vecMaxs", Data.End);

				SDKHook(entity, SDKHook_StartTouchPost, Zones_StartTouch);
				SDKHook(entity, SDKHook_TouchPost, Zones_Touch);
				SDKHook(entity, SDKHook_EndTouchPost, Zones_EndTouch);
				SDKHook(entity, SDKHook_StartTouchPost, Zones_StartTouchPost);
				SDKHook(entity, SDKHook_TouchPost, Zones_TouchPost);
				SDKHook(entity, SDKHook_EndTouchPost, Zones_EndTouchPost);
			}
		}

		case ZONE_TYPE_CIRCLE:
		{
			entity = CreateEntityByName("info_target");

			if (IsValidEntity(entity))
			{
				DispatchKeyValue(entity, "targetname", Data.Name);
				DispatchKeyValueVector(entity, "origin", Data.Start);
				DispatchSpawn(entity);
			}
		}

		case ZONE_TYPE_POLY:
		{
			entity = CreateEntityByName("info_target");

			if (IsValidEntity(entity))
			{
				DispatchKeyValue(entity, "targetname", Data.Name);
				DispatchKeyValueVector(entity, "origin", Data.Start);
				DispatchSpawn(entity);

				delete Zone[entity].PointsData;

				if (Data.PointsData != null)
				{
					Zone[entity].PointsData = view_as<ArrayList>(CloneHandle(Data.PointsData));
				}
				else
				{
					Zone[entity].PointsData = new ArrayList(3);
				}

				Zone[entity].PointsHeight = Data.PointsHeight;

				float tempMin[3];
				float tempMax[3];
				float greatdiff;

				for (int i = 0; i < Zone[entity].PointsData.Length; i++)
				{
					float coordinates[3];
					Zone[entity].PointsData.GetArray(i, coordinates, sizeof(coordinates));

					for (int j = 0; j < 3; j++)
					{
						if(tempMin[j] == 0.0 || tempMin[j] > coordinates[j]) {
							tempMin[j] = coordinates[j];
						}
						if(tempMax[j] == 0.0 || tempMax[j] < coordinates[j]) {
							tempMax[j] = coordinates[j];
						}
					}

					float coordinates2[3];
					Zone[entity].PointsData.GetArray(0, coordinates2, sizeof(coordinates2));

					float diff = CalculateHorizontalDistance(coordinates2, coordinates, false);
					if(diff > greatdiff) {
						greatdiff = diff;
					}
				}

				for (int y = 0; y < 3; y++)
				{
					Zone[entity].PointsMin[y] = tempMin[y];
					Zone[entity].PointsMax[y] = tempMax[y];
				}

				Zone[entity].PointsDistance = greatdiff;
			}
		}
	}

	if (IsValidEntity(entity))
	{
		g_aZoneEntities.Push(EntIndexToEntRef(entity));

		Zone[entity].Radius = Data.Radius;

		if (Zone[entity].Effects != null)
		{
			StringMapSnapshot snap1 = Zone[entity].Effects.Snapshot();
			char sKey[128];
			for (int j = 0; j < snap1.Length; j++)
			{
				snap1.GetKey(j, sKey, sizeof(sKey));

				StringMap temp = null;
				Zone[entity].Effects.GetValue(sKey, temp);
				delete temp;
			}
			delete snap1;
		}

		delete Zone[entity].Effects;

		if (Data.Effects != null)
		{
			Zone[entity].Effects = view_as<StringMap>(CloneHandle(Data.Effects));
		}
		else
		{
			Zone[entity].Effects = new StringMap();
		}

		Zone[entity].Color = Data.iColors;
	}

	LogMessage("Zone %s has been spawned %s as a %s zone with the entity index %i.", Data.Name, IsValidEntity(entity) ? "successfully" : "not successfully", sType, entity);

	delete Data.PointsData;
	delete Data.Effects;
	
	return entity;
}

Action IsNearExternalZone(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Action result = Plugin_Continue;

	if (!g_bIsInsideZone[client][entity])
	{
		Call_StartForward(Forward.StartTouchZone);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish(result);

		g_bIsInsideZone[client][entity] = true;
	}
	else
	{
		Call_StartForward(Forward.TouchZone);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish(result);
	}

	return result;
}

Action IsNotNearExternalZone(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Action result = Plugin_Continue;

	if (g_bIsInsideZone[client][entity])
	{
		Call_StartForward(Forward.EndTouchZone);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish(result);

		g_bIsInsideZone[client][entity] = false;
	}

	return result;
}

void IsNearExternalZone_Post(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (!g_bIsInsideZone_Post[client][entity])
	{
		CallEffectCallback(entity, client, EFFECT_CALLBACK_ONENTERZONE);

		Call_StartForward(Forward.StartTouchZone_Post);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish();

		g_bIsInsideZone_Post[client][entity] = true;

		g_bIsInZone[client][entity] = true;
	}
	else
	{
		CallEffectCallback(entity, client, EFFECT_CALLBACK_ONACTIVEZONE);

		Call_StartForward(Forward.TouchZone_Post);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish();
	}
}

void IsNotNearExternalZone_Post(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (g_bIsInsideZone_Post[client][entity])
	{
		CallEffectCallback(entity, client, EFFECT_CALLBACK_ONLEAVEZONE);

		Call_StartForward(Forward.EndTouchZone_Post);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish();

		g_bIsInsideZone_Post[client][entity] = false;

		g_bIsInZone[client][entity] = false;
	}
}

public Action Zones_StartTouch(int entity, int other)
{
	int client = other;

	if (!IsClientValid(client))
	{
		return Plugin_Continue;
	}

	g_bIsInZone[client][entity] = true;

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(Forward.StartTouchZone);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);

	Action result = Plugin_Continue;
	Call_Finish(result);

	return result;
}

public Action Zones_Touch(int entity, int other)
{
	int client = other;

	if (!IsClientValid(client))
	{
		return Plugin_Continue;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(Forward.TouchZone);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);

	Action result = Plugin_Continue;
	Call_Finish(result);

	return result;
}

public Action Zones_EndTouch(int entity, int other)
{
	int client = other;

	if (!IsClientValid(client))
	{
		return Plugin_Continue;
	}

	g_bIsInZone[client][entity] = false;

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(Forward.EndTouchZone);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);

	Action result = Plugin_Continue;
	Call_Finish(result);

	return result;
}

public void Zones_StartTouchPost(int entity, int other)
{
	int client = other;

	if (!IsClientValid(client))
	{
		return;
	}

	CallEffectCallback(entity, client, EFFECT_CALLBACK_ONENTERZONE);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(Forward.StartTouchZone_Post);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);
	Call_Finish();
}

public void Zones_TouchPost(int entity, int other)
{
	int client = other;

	if (!IsClientValid(client))
	{
		return;
	}

	CallEffectCallback(entity, client, EFFECT_CALLBACK_ONACTIVEZONE);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(Forward.TouchZone_Post);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);
	Call_Finish();
}

public void Zones_EndTouchPost(int entity, int other)
{
	int client = other;

	if (!IsClientValid(client))
	{
		return;
	}

	CallEffectCallback(entity, client, EFFECT_CALLBACK_ONLEAVEZONE);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(Forward.EndTouchZone_Post);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);
	Call_Finish();
}

void CallEffectCallback(int entity, int client, int callback)
{
	for (int i = 0; i < g_aEffectsList.Length; i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		g_aEffectsList.GetString(i, sEffect, sizeof(sEffect));

		Handle callbacks[MAX_EFFECT_CALLBACKS];
		StringMap values = null;
		if (g_smEffectCalls.GetArray(sEffect, callbacks, sizeof(callbacks)) && callbacks[callback] != null && GetForwardFunctionCount(callbacks[callback]) > 0 && Zone[entity].Effects.GetValue(sEffect, values))
		{
			Call_StartForward(callbacks[callback]);
			Call_PushCell(client);
			Call_PushCell(entity);
			Call_PushCell(values);
			Call_Finish();
		}
	}
}

void DeleteZone(int entity, bool permanent = false)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	int index = g_aZoneEntities.FindValue(EntIndexToEntRef(entity));
	g_aZoneEntities.Erase(index);

	StringMapSnapshot snap1 = Zone[entity].Effects.Snapshot();
	char sKey[128];
	for (int j = 0; j < snap1.Length; j++)
	{
		snap1.GetKey(j, sKey, sizeof(sKey));

		StringMap temp = null;
		Zone[entity].Effects.GetValue(sKey, temp);
		delete temp;
	}
	delete snap1;

	delete Zone[entity].Effects;
	delete Zone[entity].PointsData;

	RemoveEntity(entity);

	if (permanent)
	{
		g_kvConfig.Rewind();
		if (g_kvConfig.JumpToKey(sName))
		{
			g_kvConfig.DeleteThis();
		}

		SaveMapConfig();
	}
}

void RegisterNewEffect(Handle plugin, const char[] effect_name, Function function1 = INVALID_FUNCTION, Function function2 = INVALID_FUNCTION, Function function3 = INVALID_FUNCTION)
{
	if (plugin == null || strlen(effect_name) == 0)
	{
		return;
	}

	Handle callbacks[MAX_EFFECT_CALLBACKS];
	int index = g_aEffectsList.FindString(effect_name);

	if (index != -1)
	{
		g_smEffectCalls.GetArray(effect_name, callbacks, sizeof(callbacks));

		for (int i = 0; i < MAX_EFFECT_CALLBACKS; i++)
		{
			delete callbacks[i];
		}

		ClearKeys(effect_name);

		g_smEffectCalls.Remove(effect_name);
		g_aEffectsList.Erase(index);
	}

	if (function1 != INVALID_FUNCTION)
	{
		callbacks[EFFECT_CALLBACK_ONENTERZONE] = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		AddToForward(callbacks[EFFECT_CALLBACK_ONENTERZONE], plugin, function1);
	}

	if (function2 != INVALID_FUNCTION)
	{
		callbacks[EFFECT_CALLBACK_ONACTIVEZONE] = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		AddToForward(callbacks[EFFECT_CALLBACK_ONACTIVEZONE], plugin, function2);
	}

	if (function3 != INVALID_FUNCTION)
	{
		callbacks[EFFECT_CALLBACK_ONLEAVEZONE] = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		AddToForward(callbacks[EFFECT_CALLBACK_ONLEAVEZONE], plugin, function3);
	}

	g_smEffectCalls.SetArray(effect_name, callbacks, sizeof(callbacks));
	g_aEffectsList.PushString(effect_name);
}

void RegisterNewEffectKey(const char[] effect_name, const char[] key, const char[] defaultvalue)
{
	StringMap keys = null;

	if (!g_smEffectKeys.GetValue(effect_name, keys) || keys == null)
	{
		keys = new StringMap();
	}

	keys.SetString(key, defaultvalue);
	g_smEffectKeys.SetValue(effect_name, keys);
}

void ClearKeys(const char[] effect_name)
{
	StringMap keys = null;
	if (g_smEffectKeys.GetValue(effect_name, keys))
	{
		delete keys;
		g_smEffectKeys.Remove(effect_name);
	}
}

void GetMiddleOfABox(const float vec1[3], const float vec2[3], float buffer[3])
{
	float mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);

	mid[0] /= 2.0;
	mid[1] /= 2.0;
	mid[2] /= 2.0;

	AddVectors(vec1, mid, buffer);
}

bool GetClientLookPoint(int client, float lookposition[3], bool beam = false)
{
	float vEyePos[3];
	GetClientEyePosition(client, vEyePos);

	float vEyeAng[3];
	GetClientEyeAngles(client, vEyeAng);

	Handle hTrace = TR_TraceRayFilterEx(vEyePos, vEyeAng, MASK_SHOT, RayType_Infinite, TraceEntityFilter_NoPlayers);
	bool bHit = TR_DidHit(hTrace);

	TR_GetEndPosition(lookposition, hTrace);

	delete hTrace;

	if (beam && !IsNullVector(lookposition) && !IsNullVector(vEyePos))
	{
		int iColor[4];

		iColor[0] = 255;
		iColor[1] = 20;
		iColor[2] = 147;
		iColor[3] = 255;

		if (strlen(CZone[client].Color) > 0)
		{
			g_smColorData.GetArray(CZone[client].Color, iColor, sizeof(iColor));
		}
		
		TE_SetupBeamPointsToClient(client, vEyePos, lookposition, g_iDefaultModelIndex, g_iDefaultHaloIndex, TE_STARTFRAME, TE_FRAMERATE, TE_LIFE, TE_WIDTH, TE_ENDWIDTH, TE_FADELENGTH, TE_AMPLITUDE, iColor, TE_SPEED);
	}

	return bHit;
}

public bool TraceEntityFilter_NoPlayers(int entity, int contentsMask)
{
	return false;
}

void Array_Copy(const any[] array, any[] newArray, int size)
{
	for (int i = 0; i < size; i++)
	{
		newArray[i] = array[i];
	}
}

void TE_DrawBeamBoxToClient(int client, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame, int frameRate, float life, float width, float endWidth, int fadeLength, float amplitude, const color[4], int speed)
{
	int clients[1];
	clients[0] = client;
	TE_DrawBeamBox(clients, 1, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

// This is never used
stock void TE_DrawBeamBoxToAll(const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame, int frameRate, float life, float width, float endWidth, int fadeLength, float amplitude, const color[4], int speed)
{
	int[] clients = new int[MaxClients];
	int numClients;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			clients[numClients++] = i;
		}
	}

	TE_DrawBeamBox(clients, numClients, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

void TE_DrawBeamBox(int[] clients,int numClients, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame, int frameRate, float life, float width, float endWidth, int fadeLength, float amplitude, const color[4], int speed)
{
	float corners[8][3];

	for (int i = 0; i < 4; i++)
	{
		Array_Copy(bottomCorner, corners[i], 3);
		Array_Copy(upperCorner, corners[i + 4], 3);
	}

	corners[1][0] = upperCorner[0];
	corners[2][0] = upperCorner[0];
	corners[2][1] = upperCorner[1];
	corners[3][1] = upperCorner[1];
	corners[4][0] = bottomCorner[0];
	corners[4][1] = bottomCorner[1];
	corners[5][1] = bottomCorner[1];
	corners[7][0] = bottomCorner[0];

	for (int i = 0; i < 4; i++)
	{
		int j = ( i == 3 ? 0 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for (int i = 4; i < 8; i++)
	{
		int j = ( i == 7 ? 4 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for (int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i+4], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}
}

void TE_SetupBeamRingPointToClient(int client, const float center[3], float Start_Radius, float End_Radius, int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float Amplitude, const int Color[4], int Speed, int Flags)
{
	TE_SetupBeamRingPoint(center, Start_Radius, End_Radius, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, Amplitude, Color, Speed, Flags);
	TE_SendToClient(client);
}

void TE_SetupBeamPointsToClient(int client, const float start[3], const float end[3], int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float EndWidth, int FadeLength, float Amplitude, const int Color[4], int Speed)
{
	TE_SetupBeamPoints(start, end, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
}

void ParseColorsData()
{
	g_aColors.Clear();
	g_smColorData.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/zone_colors.cfg");

	KeyValues kv = new KeyValues("zone_colors");

	int color[4];
	char sBuffer[64];

	if (FileExists(sPath))
	{
		if (kv.ImportFromFile(sPath) && kv.GotoFirstSubKey(false))
		{
			do
			{
				char sColor[64];
				kv.GetSectionName(sColor, sizeof(sColor));

				kv.GetColor(NULL_STRING, color[0], color[1], color[2], color[3]);

				g_aColors.PushString(sColor);
				g_smColorData.SetArray(sColor, color, sizeof(color));
			}
			while (kv.GotoNextKey(false));
		}
	}
	else
	{
		g_aColors.PushString("Clear");
		color = {255, 255, 255, 0};
		g_smColorData.SetArray("Clear", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("Clear", sBuffer);

		g_aColors.PushString("Red");
		color = {255, 0, 0, 255};
		g_smColorData.SetArray("Red", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("Red", sBuffer);

		g_aColors.PushString("Green");
		color = {0, 255, 0, 255};
		g_smColorData.SetArray("Green", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("Green", sBuffer);

		g_aColors.PushString("Blue");
		color = {0, 0, 255, 255};
		g_smColorData.SetArray("Blue", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("Blue", sBuffer);

		g_aColors.PushString("Yellow");
		color = {255, 255, 0, 255};
		g_smColorData.SetArray("Yellow", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("Yellow", sBuffer);

		g_aColors.PushString("White");
		color = {255, 255, 255, 255};
		g_smColorData.SetArray("White", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("White", sBuffer);

		g_aColors.PushString("Pink");
		color = {255, 20, 147, 255};
		g_smColorData.SetArray("Pink", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		kv.SetString("Pink", sBuffer);

		KeyValuesToFile(kv, sPath);
	}

	delete kv;
	LogMessage("Successfully parsed %i colors for zones.", g_aColors.Length);
}

bool TeleportToZone(int client, const char[] zone)
{
	if (!IsClientValid(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	int entity = -1; char sName[64]; bool bFound = false;
	for (int i = 0; i < g_aZoneEntities.Length; i++)
	{
		entity = EntRefToEntIndex(g_aZoneEntities.Get(i));

		if (IsValidEntity(entity))
		{
			GetEntPropString(entity, Prop_Send, "m_iName", sName, sizeof(sName));

			if (StrEqual(sName, zone))
			{
				bFound = true;
				break;
			}
		}
	}

	if (!bFound)
	{
		PrintToChat(client, "Sorry, couldn't find the zone '%s' for you to teleport to.", zone);
		return false;
	}

	float fMiddle[3];
	switch (GetZoneTypeByIndex(entity))
	{
		case ZONE_TYPE_BOX:
		{
			float start[3];
			GetZonesVectorData(entity, "start", start);

			float end[3];
			GetZonesVectorData(entity, "end", end);

			GetMiddleOfABox(start, end, fMiddle);
		}

		case ZONE_TYPE_CIRCLE:
		{
			GetZonesVectorData(entity, "start", fMiddle);
		}

		case ZONE_TYPE_POLY:
		{
			PrintToChat(client, "Sorry, Polygon zones aren't currently supported for teleporting.");
			return false;
		}
	}

	TeleportEntity(client, fMiddle, NULL_VECTOR, NULL_VECTOR);
	PrintToChat(client, "You have been teleported to '%s'.", zone);

	return true;
}

//Down to just above the natives, these functions are made by 'Deathknife' and repurposed by me for this plugin.
//Fucker can maths
//by Deathknife
bool IsPointInZone(float point[3], int zone)
{
	//Check if point is in the zone
	if (!IsOriginInBox(point, zone))
	{
		return false;
	}

	//Get a ray outside of the polygon
	float ray[3];
	ray = point;
	ray[1] += Zone[zone].PointsDistance + 50.0;
	ray[2] = point[2];

	//Store the x and y intersections of where the ray hits the line
	float xint;
	float yint;

	//Intersections for base bottom and top(2)
	float baseY;
	float baseZ;
	float baseY2;
	float baseZ2;

	//Calculate equation for x + y
	float eq[2];
	eq[0] = point[0] - ray[0];
	eq[1] = point[2] - ray[2];

	//This is for checking if the line intersected the base
	//The method is messy, came up with it myself, and might not work 100% of the time.
	//Should work though.

	//Bottom
	int lIntersected[64];
	float fIntersect[64][3];

	//Top
	int lIntersectedT[64];
	float fIntersectT[64][3];

	//Count amount of intersetcions
	int intersections = 0;

	//Count amount of intersection for BASE
	int lIntNum = 0;
	int lIntNumT = 0;

	//Get slope
	float lSlope = (ray[2] - point[2]) / (ray[1] - point[1]);
	float lEq = (lSlope & ray[0]) - ray[2];
	lEq = -lEq;

	//Get second slope
	//float lSlope2 = (ray[1] - point[1]) / (ray[0] - point[0]);
	//float lEq2 = (lSlope2 * point[0]) - point[1];
	//lEq2 = -lEq2;

	//Loop through every point of the zone
	int size = Zone[zone].PointsData.Length;

	for (int i = 0; i < size; i++)
	{
		//Get current & next point
		float currentpoint[3];
		Zone[zone].PointsData.GetArray(i, currentpoint, sizeof(currentpoint));

		float nextpoint[3];

		//Check if its the last point, if it is, join it with the first
		if (size == i + 1)
		{
			Zone[zone].PointsData.GetArray(0, nextpoint, sizeof(nextpoint));
		}
		else
		{
			Zone[zone].PointsData.GetArray(i + 1, nextpoint, sizeof(nextpoint));
		}

		//Check if the ray intersects the point
		//Ignore the height parameter as we will check against that later
		bool didinter = get_line_intersection(ray[0], ray[1], point[0], point[1], currentpoint[0], currentpoint[1], nextpoint[0], nextpoint[1], xint, yint);

		//Get intersections of the bottom
		bool baseInter = get_line_intersection(ray[1], ray[2], point[1], point[2], currentpoint[1], currentpoint[2], nextpoint[1], nextpoint[2], baseY, baseZ);

		//Get intersections of the top
		bool baseInter2 = get_line_intersection(ray[1], ray[2], point[1], point[2], currentpoint[1] + Zone[zone].PointsHeight, currentpoint[2] + Zone[zone].PointsHeight, nextpoint[1] + Zone[zone].PointsHeight, nextpoint[2] + Zone[zone].PointsHeight, baseY2, baseZ2);

		//If base intersected, store the line for later
		if (baseInter && lIntNum < sizeof(fIntersect))
		{
			lIntersected[lIntNum] = i;
			fIntersect[lIntNum][1] = baseY;
			fIntersect[lIntNum][2] = baseZ;
			lIntNum++;
		}

		if (baseInter2 && lIntNumT < sizeof(fIntersectT))
		{
			lIntersectedT[lIntNumT] = i;
			fIntersectT[lIntNumT][1] = baseY2;
			fIntersectT[lIntNum][2] = baseZ2;
			lIntNumT++;
		}

		//If ray intersected line, check against height
		if (didinter)
		{
			//Get the height of intersection

			//Get slope of line it hit
			float m1 = (nextpoint[2] - currentpoint[2]) / (nextpoint[0] - currentpoint[0]);

			//Equation y = mx + c | mx - y = -c
			float l1 = (m1 * currentpoint[0]) - currentpoint[2];
			l1 = -l1;

			float y2 = (m1 * xint) + l1;

			//Get slope of ray
			float y = (lSlope * xint) + lEq;

			if (y > y2 && y < y2 + 128.0 + Zone[zone].PointsHeight)
			{
				//The ray intersected the line and is within the height
				intersections++;
			}
		}
	}

	//Now we check for base hitting
	//This method is weird, but works most of the time
	for (int k = 0; k < lIntNum; k++)
	{
		for (int l = k + 1; l < lIntNum; l++)
		{
			if (l == k)
			{
				continue;
			}

			int i = lIntersected[k];
			int j = lIntersected[l];

			if (i == j)
			{
				continue;
			}

			float currentpoint[2][3];
			float nextpoint[2][3];

			if (Zone[zone].PointsData.Length == i + 1)
			{
				Zone[zone].PointsData.GetArray(i, currentpoint[0], 3);
				Zone[zone].PointsData.GetArray(0, nextpoint[0], 3);
			}
			else
			{
				Zone[zone].PointsData.GetArray(i, currentpoint[0], 3);
				Zone[zone].PointsData.GetArray(i + 1, nextpoint[0], 3);
			}

			if (Zone[zone].PointsData.Length == j + 1)
			{
				Zone[zone].PointsData.GetArray(j, currentpoint[1], 3);
				Zone[zone].PointsData.GetArray(0, nextpoint[1], 3);
			}
			else
			{
				Zone[zone].PointsData.GetArray(j, currentpoint[1], 3);
				Zone[zone].PointsData.GetArray(j + 1, nextpoint[1], 3);
			}

			//Get equation of both lines then find slope of them
			float m1 = (nextpoint[0][1] - currentpoint[0][1]) / (nextpoint[0][0] - currentpoint[0][0]);
			float m2 = (nextpoint[1][1] - currentpoint[1][1]) / (nextpoint[1][0] - currentpoint[1][0]);
			float lEq1 = (m1 * currentpoint[0][0]) - currentpoint[0][1];
			float lEq2 = (m2 * currentpoint[1][0]) - currentpoint[1][1];
			lEq1 = -lEq1;
			lEq2 = -lEq2;

			//Get x point of intersection
			float xPoint1 = ((fIntersect[k][1] - lEq1) / m1);
			float xPoint2 = ((fIntersect[l][1] - lEq2 / m2));

			if (xPoint1 > point[0] > xPoint2 || xPoint1 < point[0] < xPoint2)
			{
				intersections++;
			}
		}
	}

	for (int k = 0; k < lIntNumT; k++)
	{
		for (int l = k + 1; l < lIntNumT; l++)
		{
			if (l == k)
			{
				continue;
			}

			int i = lIntersectedT[k];
			int j = lIntersectedT[l];

			if (i == j)
			{
				continue;
			}

			float currentpoint[2][3];
			float nextpoint[2][3];

			if (Zone[zone].PointsData.Length == i + 1)
			{
				Zone[zone].PointsData.GetArray(i, currentpoint[0], 3);
				Zone[zone].PointsData.GetArray(0, nextpoint[0], 3);
			}
			else
			{
				Zone[zone].PointsData.GetArray(i, currentpoint[0], 3);
				Zone[zone].PointsData.GetArray(i + 1, nextpoint[0], 3);
			}

			if (Zone[zone].PointsData.Length == j + 1)
			{
				Zone[zone].PointsData.GetArray(j, currentpoint[1], 3);
				Zone[zone].PointsData.GetArray(0, nextpoint[1], 3);
			}
			else
			{
				Zone[zone].PointsData.GetArray(j, currentpoint[1], 3);
				Zone[zone].PointsData.GetArray(j + 1, nextpoint[1], 3);
			}

			//Get equation of both lines then find slope of them
			float m1 = (nextpoint[0][1] - currentpoint[0][1]) / (nextpoint[0][0] - currentpoint[0][0]);
			float m2 = (nextpoint[1][1] - currentpoint[1][1]) / (nextpoint[1][0] - currentpoint[1][0]);
			float lEq1 = (m1 * currentpoint[0][0]) - currentpoint[0][1];
			float lEq2 = (m2 * currentpoint[1][0]) - currentpoint[1][1];
			lEq1 = -lEq1;
			lEq2 = -lEq2;

			//Get x point of intersection
			float xPoint1 = ((fIntersectT[k][1] - lEq1) / m1);
			float xPoint2 = ((fIntersectT[l][1] - lEq2 / m2));

			if (xPoint1 > point[0] > xPoint2 || xPoint1 < point[0] < xPoint2)
			{
				intersections++;
			}
		}
	}

	if (intersections <= 0 || intersections % 2 == 0)
	{
		return false;
	}

	return true;
}

bool IsOriginInBox(float origin[3], int zone)
{
	if(origin[0] >= Zone[zone].PointsMin[0] && origin[1] >= Zone[zone].PointsMin[1] && origin[2] >= Zone[zone].PointsMin[2] && origin[0] <= Zone[zone].PointsMax[0] + Zone[zone].PointsHeight && origin[1] <= Zone[zone].PointsMax[1] + Zone[zone].PointsHeight && origin[2] <= Zone[zone].PointsMax[2] + Zone[zone].PointsHeight)
	{
		return true;
	}

	return false;
}

bool get_line_intersection(float p0_x, float p0_y, float p1_x, float p1_y, float p2_x, float p2_y, float p3_x, float p3_y, float &i_x, float &i_y)
{
	float s1_x = p1_x - p0_x;
	float s1_y = p1_y - p0_y;
	float s2_x = p3_x - p2_x;
	float s2_y = p3_y - p2_y;

	float s = (-s1_y * (p0_x - p2_x) + s1_x * (p0_y - p2_y)) / (-s2_x * s1_y + s1_x * s2_y);
	float t = ( s2_x * (p0_y - p2_y) - s2_y * (p0_x - p2_x)) / (-s2_x * s1_y + s1_x * s2_y);

	if (s >= 0 && s <= 1 && t >= 0 && t <= 1)
	{
		// Collision detected
		i_x = p0_x + (t * s1_x);
		i_y = p0_y + (t * s1_y);

		return true;
	}

	return false; // No collision
}

float CalculateHorizontalDistance(float vec1[3], float vec2[3], bool squared = false)
{
	if (squared)
	{
		if (vec1[0] < 0.0)
		{
			vec1[0] *= -1;
		}

		if (vec1[1] < 0.0)
		{
			vec1[1] *= -1;
		}

		vec1[0] = SquareRoot(vec1[0]);
		vec1[1] = SquareRoot(vec1[1]);

		if (vec2[0] < 0.0)
		{
			vec2[0] *= -1;
		}

		if (vec2[1] < 0.0)
		{
			vec2[1] *= -1;
		}

		vec2[0] = SquareRoot(vec2[0]);
		vec2[1] = SquareRoot(vec2[1]);
	}

	return SquareRoot( Pow((vec1[0] - vec2[0]), 2.0) +  Pow((vec1[1] - vec2[1]), 2.0) );
}

//Natives
public int Native_Register_Effect(Handle plugin, int numParams)
{
	int size;
	GetNativeStringLength(1, size);

	char[] sEffect = new char[size + 1];
	GetNativeString(1, sEffect, size + 1);

	Function function1 = GetNativeFunction(2);
	Function function2 = GetNativeFunction(3);
	Function function3 = GetNativeFunction(4);

	RegisterNewEffect(plugin, sEffect, function1, function2, function3);
}

public int Native_Register_Effect_Key(Handle plugin, int numParams)
{
	int size;
	GetNativeStringLength(1, size);

	char[] sEffect = new char[size + 1];
	GetNativeString(1, sEffect, size + 1);

	size = 0;
	GetNativeStringLength(2, size);

	char[] sKey = new char[size + 1];
	GetNativeString(2, sKey, size + 1);

	size = 0;
	GetNativeStringLength(3, size);

	char[] sDefaultValue = new char[size + 1];
	GetNativeString(3, sDefaultValue, size + 1);

	RegisterNewEffectKey(sEffect, sKey, sDefaultValue);
}

public int Native_Request_QueueEffects(Handle plugin, int numParams)
{
	QueueEffects();
}

public int Native_IsClientInZone(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!IsClientValid(client))
	{
		return false;
	}

	int size;
	GetNativeStringLength(2, size);

	char[] sName = new char[size + 1];
	GetNativeString(2, sName, size + 1);

	for (int i = 0; i < g_aZoneEntities.Length; i++)
	{
		int zone = EntRefToEntIndex(g_aZoneEntities.Get(i));

		if (IsValidEntity(zone))
		{
			char sName2[64];
			GetEntPropString(zone, Prop_Send, "m_iName", sName2, sizeof(sName2));

			if (StrEqual(sName, sName2))
			{
				return g_bIsInZone[client][zone];
			}
		}
	}

	return false;
}

public int Native_TeleportClientToZone(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!IsClientValid(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	int size;
	GetNativeStringLength(2, size);

	char[] sName = new char[size + 1];
	GetNativeString(2, sName, size + 1);

	return TeleportToZone(client, sName);
}

bool AddMenuItemFormat(Menu& menu, const char[] info, int style = ITEMDRAW_DEFAULT, const char[] format, any ...)
{
	char display[128];
	VFormat(display, sizeof(display), format, 5);

	return menu.AddItem(info, display, style);
}

bool IsClientValid(int client)
{
    if (client > 0 && client <= MaxClients)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client))
        {
            return true;
        }
    }

    return false;
}

void PushMenuCell(Menu hndl, const char[] id, int data)
{
	char DataString[64];
	IntToString(data, DataString, sizeof(DataString));
	hndl.AddItem(id, DataString, ITEMDRAW_IGNORE);
}

void PushMenuString(Menu hndl, const char[] id, const char[] data)
{
	hndl.AddItem(id, data, ITEMDRAW_IGNORE);
}

int GetMenuCell(Menu hndl, const char[] id, int DefaultValue = 0)
{
	int ItemCount = hndl.ItemCount;
	char info[64]; char data[64];

	for (int i = 0; i < ItemCount; i++) {
		if (hndl.GetItem(i, info, sizeof(info), _, data, sizeof(data)))
		{
			if (StrEqual(info, id))
			return StringToInt(data);
		}
	}
	return DefaultValue;
}

bool GetMenuString(Menu hndl, const char[] id, char[] Buffer, int size)
{
	int ItemCount = hndl.ItemCount;
	char info[64]; char data[64];

	for (int i = 0; i < ItemCount; i++) {
		if (hndl.GetItem(i, info, sizeof(info), _, data, sizeof(data)))
		{
			if (StrEqual(info, id)) {
				strcopy(Buffer, size, data);
				return true;
			}
		}
	}
	return false;
}

any ClampCell(any value, any min, any max)
{
	if (value < min)
	{
		value = min;
	}

	if (value > max)
	{
		value = max;
	}

	return value;
}

bool IsPositionNull(float position[3])
{
	if (position[0] == 0.0 && position[1] == 0.0 && position[2] == 0.0)
	{
		return true;
	}

	return false;
}
