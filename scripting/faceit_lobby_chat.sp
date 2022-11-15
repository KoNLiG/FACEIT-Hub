#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

bool g_InLobbyChannel[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "[FACEIT-Hub] Faceit Lobby Chat",
    author = "KoNLiG",
    description = "Provides a chat command which sets a client chat area.",
    version = "1.0.0",
    url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
    AddCommandListener(Command_Chat, "sm_chat");
}

public void OnClientDisconnect(int client)
{
    g_InLobbyChannel[client] = false;
}

Action Command_Chat(int client, const char[] command, int argc)
{
    if (!IsClientInGame(client))
    {
        return Plugin_Continue;
    }

    if (!argc)
    {
        PrintToChat(client, " \x07Invalid usage! Correct usage: /chat channel\x01");
        PrintToChat(client, " \x07Valid channels: all, lobby");
        return Plugin_Stop;
    }

    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));

    // All channel
    if (arg[0] == 'a' || arg[0] == 'A')
    {
        if (!g_InLobbyChannel[client])
        {
            PrintToChat(client, " \x07Are are already in this channel!\x01");
            return Plugin_Stop;
        }

        g_InLobbyChannel[client] = false;
        PrintToChat(client, " \x04You are now in the \x10ALL\x04 channel\x01");
    }
    // Lobby channel.
    else if (arg[0] == 'l' || arg[0] == 'L')
    {
        if (g_InLobbyChannel[client])
        {
            PrintToChat(client, " \x07Are are already in this channel!\x01");
            return Plugin_Stop;
        }

        g_InLobbyChannel[client] = true;
        PrintToChat(client, " \x04You are now in the \x10LOBBY\x04 channel\x01");
    }
    // Unknown channel.
    else
    {
        PrintToChat(client, " \x07Invalid chat channel\x01");
    }

    return Plugin_Stop;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (!g_InLobbyChannel[client])
    {
        return Plugin_Continue;
    }

    ClientCommand(client, "sm_lc %s", sArgs);

    return Plugin_Handled;
}