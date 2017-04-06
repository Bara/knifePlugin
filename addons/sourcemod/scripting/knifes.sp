#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <csgoitems>
#include <clientprefs>

#include <multicolors>

#pragma newdecls required

#define KNIFE_LENGTH 128
#define KNIFE_FLAG 32

bool g_bDebug = false;

int g_iKnife[MAXPLAYERS + 1] =  { -1, ... };
int g_iSite[MAXPLAYERS + 1] =  { 0, ... };

ConVar g_cMessage = null;
ConVar g_cShowDisableKnifes = null;

Handle g_hKnifeCookie = null;

char g_sKnifeConfig[PLATFORM_MAX_PATH + 1] = "";

public Plugin myinfo = 
{
	name = "Knifes",
	author = "Bara",
	description = "",
	version = "1.0.0",
	url = "github.com/Bara20/knifePlugin"
};

public void OnPluginStart()
{
	BuildPath(Path_SM, g_sKnifeConfig, sizeof(g_sKnifeConfig), "configs/knifes.cfg");
	
	LoadTranslations("knifes.phrases");
	
	RegConsoleCmd("sm_knife", Command_Knife);
	
	g_hKnifeCookie = RegClientCookie("knifes_cookie", "Cookie for Knife Def Index", CookieAccess_Private);
	
	g_cMessage = CreateConVar("knifes_show_message", "1", "Show message on knife selection", _, true, 0.0, true, 1.0);
	g_cShowDisableKnifes = CreateConVar("knifes_show_disabled_knife", "1", "Show disabled knifes (for user without flag)", _, true, 0.0, true, 1.0);
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	for (int i = 0; i <= MaxClients; i++)
	{
		if(IsClientValid(i))
		{
			OnClientCookiesCached(i);
		}
	}
	
	if(CSGOItems_AreItemsSynced())
	{
		UpdateKnifesConfig();
	}
}

public void CSGOItems_OnItemsSynced()
{
	UpdateKnifesConfig();
}

public void OnClientCookiesCached(int client)
{
	char sDefIndex[8];
	GetClientCookie(client, g_hKnifeCookie, sDefIndex, sizeof(sDefIndex));
	
	int iDefIndex = StringToInt(sDefIndex);
	if(iDefIndex > 0)
	{
		g_iKnife[client] = iDefIndex;
	}
}

public Action Command_Knife(int client, int args)
{
	if(!IsClientValid(client))
	{
		return Plugin_Handled;
	}
	
	ShowKnifeMenu(client);
	
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_PlayerSpawn, event.GetInt("userid"));
}

public void Frame_PlayerSpawn(any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (IsClientValid(client) && IsPlayerAlive(client))
	{
		ReplaceKnife(client);
	}
}

public int Menu_Knife(Menu menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select)
	{
		char sClassname[KNIFE_LENGTH];
		menu.GetItem(param, sClassname, sizeof(sClassname));
		int defIndex = CSGOItems_GetWeaponDefIndexByClassName(sClassname);
		
		g_iKnife[client] = defIndex;
		char sDefIndex[8];
		IntToString(g_iKnife[client], sDefIndex, sizeof(sDefIndex));
		SetClientCookie(client, g_hKnifeCookie, sDefIndex);
		
		if (g_cMessage.BoolValue)
		{
			char sDisplay[KNIFE_LENGTH];
			CSGOItems_GetWeaponDisplayNameByDefIndex(g_iKnife[client], sDisplay, sizeof(sDisplay));
			CPrintToChat(client, "%T", "Knife Choosed", client, sDisplay);
		}
		
		g_iSite[client] = menu.Selection;
		
		ReplaceKnife(client);
		RequestFrame(Frame_OpenMenu, GetClientUserId(client));
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void Frame_OpenMenu(any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (IsClientValid(client))
	{
		ShowKnifeMenu(client);
	}
}

bool IsClientValid(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		if(IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client))
		{
			return true;
		}
	}
	
	return false;
}

void ShowKnifeMenu(int client)
{
	
	Menu menu = new Menu(Menu_Knife);
	
	if (g_iKnife[client] > 0)
	{
		char sDisplay[KNIFE_LENGTH];
		CSGOItems_GetWeaponDisplayNameByDefIndex(g_iKnife[client], sDisplay, sizeof(sDisplay));
		
		if(g_iKnife[client] == 59)
		{
			Format(sDisplay, sizeof(sDisplay), "%T", "T Knife", client, sDisplay);
		}
		
		menu.SetTitle("%T", "Choose a Knife Currently", client, sDisplay);
	}
	else
	{
		menu.SetTitle("%T", "Choose a Knife", client);
	}
	
	for (int i = 0; i <= CSGOItems_GetWeaponCount(); i++)
	{
		int defIndex = CSGOItems_GetWeaponDefIndexByWeaponNum(i);
		
		if(CSGOItems_IsDefIndexKnife(defIndex))
		{
			char sClassName[KNIFE_LENGTH], sDisplayName[KNIFE_LENGTH];
			CSGOItems_GetWeaponClassNameByDefIndex(defIndex, sClassName, sizeof(sClassName));
			CSGOItems_GetWeaponDisplayNameByDefIndex(defIndex, sDisplayName, sizeof(sDisplayName));
			
			if(defIndex == 59)
			{
				Format(sDisplayName, sizeof(sDisplayName), "%T", "T Knife", client, sDisplayName);
			}
			
			char sFlags[32];
			GetKnifeFlags(sClassName, sFlags, sizeof(sFlags));
			
			bool bFlag = HasFlags(client, sFlags);
			
			if (g_bDebug)
			{
				PrintToChat(client, "%s ([%d] [%s (%d)] [%d] %s)", sDisplayName, defIndex, sFlags, strlen(sFlags), bFlag, sClassName);
			}
			
			if (bFlag && g_iKnife[client] != defIndex)
			{
				menu.AddItem(sClassName, sDisplayName);
			}
			else if (g_iKnife[client] == defIndex || (!bFlag && g_cShowDisableKnifes.BoolValue))
			{
				menu.AddItem(sClassName, sDisplayName, ITEMDRAW_DISABLED);
			}
		}
	}
	
	menu.ExitButton = true;
	menu.DisplayAt(client, g_iSite[client], MENU_TIME_FOREVER);
}

void UpdateKnifesConfig()
{
	KeyValues kvConf = new KeyValues("Knifes");
	
	if (!kvConf.ImportFromFile(g_sKnifeConfig))
	{
		ThrowError("Can' find or read the file %s...", g_sKnifeConfig);
		return;
	}
	
	for (int i = 0; i <= CSGOItems_GetWeaponCount(); i++)
	{
		int defIndex = CSGOItems_GetWeaponDefIndexByWeaponNum(i);
		
		if(CSGOItems_IsDefIndexKnife(defIndex))
		{
			char sClassName[KNIFE_LENGTH], sDisplayName[KNIFE_LENGTH];
			CSGOItems_GetWeaponClassNameByDefIndex(defIndex, sClassName, sizeof(sClassName));
			CSGOItems_GetWeaponDisplayNameByDefIndex(defIndex, sDisplayName, sizeof(sDisplayName));
			
			if(defIndex == 59)
			{
				Format(sDisplayName, sizeof(sDisplayName), "%T", "T Knife", LANG_SERVER, sDisplayName);
			}
			
			kvConf.JumpToKey(sClassName, true);
			kvConf.SetString("name", sDisplayName);
			kvConf.SetNum("defIndex", defIndex);
			
			kvConf.Rewind();
		}
	}
	
	kvConf.ExportToFile(g_sKnifeConfig);
	delete kvConf;
}

void GetKnifeFlags(const char[] className, char[] flags, int size)
{
	KeyValues kvConf = new KeyValues("Knifes");
	
	if (!kvConf.ImportFromFile(g_sKnifeConfig))
	{
		ThrowError("Can' find or read the file %s...", g_sKnifeConfig);
		return;
	}
	
	kvConf.JumpToKey(className);
	kvConf.GetString("flag", flags, size);
	
	delete kvConf;
}

bool HasFlags(int client, char[] flags)
{
	if(strlen(flags) == 0)
	{
		return true;
	}
	
	int iFlags = GetUserFlagBits(client);
	
	if (iFlags & ADMFLAG_ROOT)
	{
		return true;
	}
	
	AdminFlag aFlags[16];
	FlagBitsToArray(ReadFlagString(flags), aFlags, sizeof(aFlags));
	
	for (int i = 0; i < sizeof(aFlags); i++)
	{
		if (iFlags & FlagToBit(aFlags[i]))
		{
			return true;
		}
	}
	
	return false;
}

void ReplaceKnife(int client)
{
	if(g_iKnife[client] > 0)
	{
		char sClassname[32];
		CSGOItems_GetWeaponClassNameByDefIndex(g_iKnife[client], sClassname, sizeof(sClassname));
		CSGOItems_RemoveKnife(client);
		int iKnife = GivePlayerItem(client, sClassname);
		EquipPlayerWeapon(client, iKnife);
	}
}
