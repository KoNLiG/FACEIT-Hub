// TODO LIST:
// 1. Implement max lobby slots by enforcing 'faceit_hub_lobby_slots'
#include <sourcemod>
#include <regex>
#include <socket>
#include <bytebuffer>
#include <Faceit-API>
#include <Faceit-API/helpers>

#pragma semicolon 1
#pragma newdecls required

// String lengths declarations.
#define MAX_IPV4_LENGTH 16
#define MAX_SOCKET_KEY_LENGTH 32
#define MAX_PLAYER_ID_LENGTH 64

#define LINE_BREAK "\xE2\x80\xA9"

#define SEPERATOR " \x0C\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E" ... \
"\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF"

// ConVars definitions. Handled in 'configuration.sp'
ConVar faceit_hub_socket_key;
ConVar faceit_hub_socket_reconnect_interval;
ConVar faceit_hub_socket_ip;
ConVar faceit_hub_socket_port;
ConVar faceit_hub_lobby_slots;
ConVar faceit_hub_lobby_invite_expiration;
ConVar faceit_hub_lobby_create_message;
ConVar faceit_hub_lobby_chat_cooldown;
ConVar faceit_hub_lobby_create_cooldown;

bool g_Lateload;

// Must be included after all definitions.
#define COMPILING_FROM_MAIN
#include "faceit_hub/structs.sp"
#include "faceit_hub/socket.sp"
#include "faceit_hub/interface.sp"
#include "faceit_hub/configuration.sp"
#undef COMPILING_FROM_MAIN

public Plugin myinfo =
{
    name = "FACEIT-Hub",
    author = "KoNLiG",
    description = "Provides an in-game cross server FACEIT hub.",
    version = "1.0.0",
    url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_Lateload = late;

    return APLRes_Success;
}

public void OnPluginStart()
{
    InitializeCvars();

    RegisterCommands();

    InitializeGlobals();

    SetupClientSocket();

    // 'OnClientAuthorized'/'OnClientDisconnect' replacements.
    HookEvent("player_connect", Event_PlayerConnect);
    HookEvent("player_disconnect", Event_PlayerDisconnect);
}

// Very important in order to keep a proper sync between all the servers.
public void OnPluginEnd()
{
    Player player;
    FaceitLobby faceit_lobby;

    for (int current_player = g_Players.Length - 1; current_player >= 0; current_player--)
    {
        g_Players.GetArray(current_player, player);

        bool is_leader;
        if (!player.GetFaceitLobby(faceit_lobby, is_leader) || !player.IsLocal())
        {
            continue;
        }

        if (is_leader)
        {
            SendLobbyCreatePacket(faceit_lobby.uuid, player.steamid64, false);
        }
        else
        {
            SendJoinPacket(faceit_lobby.uuid, player.steamid64, false);
        }

        SendPlayerConnectPacket(player.steamid64, false);
    }
}

public void OnMapStart()
{
    Player player;

    for (int current_client = 1, idx; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && player.GetByIndex(current_client, idx))
        {
            player.cooldown.Reset();
            player.UpdateMyself(idx);
        }
    }
}

void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
    char networkid[MAX_AUTHID_LENGTH];
    event.GetString("networkid", networkid, sizeof(networkid));

    GetSteam64FromSteam2(networkid, networkid);

    OnPlayerConnect(networkid);
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client)
    {
        OnPlayerDisconnect(client);
    }
}

void OnPlayerConnect(const char[] steamid64, bool late_load = false)
{
    SendPlayerConnectPacket(steamid64, .late_load = late_load);
}

void OnPlayerDisconnect(int client)
{
    Player player;
    if (player.GetByIndex(client))
    {
        SendPlayerConnectPacket(player.steamid64, false);
    }
}

// Fixes the created menu gap when Exit-Back button is applied.
void FixMenuGap(Menu menu, int ignored_items = 0)
{
    int max_items = 6 - menu.ItemCount + ignored_items;
    for (int current_item; current_item < max_items; current_item++)
    {
        menu.AddItem("", "", ITEMDRAW_NOTEXT);
    }
}

void PrintToChatSeperators(int client, const char[] format, any...)
{
    char message[256];
    VFormat(message, sizeof(message), format, 3);

    PrintToChat(client, SEPERATOR);
    PrintToChat(client, "%s", message);
    PrintToChat(client, SEPERATOR);
}

void GetSteam64FromSteam2(const char[] steamid2, char steamid64[MAX_AUTHID_LENGTH])
{
    int result[2];

    result[0] = StringToInt(steamid2[10]) * 2 + (steamid2[8] - 48);
    result[1] = 0x01100001; // 76561197960265728 >> 32

    Int64ToString(result, steamid64, sizeof(steamid64));
}