#assert defined COMPILING_FROM_MAIN

char g_ServerName[32];

void InitializeCvars()
{
    // Initialize convars.

    // Game Cvars.
    ConVar hostname = FindConVar("hostname");
    if (hostname)
    {
        char hostname_str[64];
        hostname.GetString(hostname_str, sizeof(hostname_str));

        int idx = FindCharInString(hostname_str, '#');
        if (idx != -1)
        {
            Format(g_ServerName, sizeof(g_ServerName), "\x03[%s]\x0E ", hostname_str[idx + 2]);
        }
    }

    // Socket.
    faceit_hub_socket_key = CreateConVar("faceit_hub_socket_key", "PASSWORD", "Key used to transfer data between sockets. Up to 32 characters.", FCVAR_HIDDEN);
    faceit_hub_socket_reconnect_interval = CreateConVar("faceit_hub_socket_reconnect_interval", "60", "Reconnect interval of client server with listen server. (represented in seconds)")
    faceit_hub_socket_ip = CreateConVar("faceit_hub_socket_ip", "", "IP used to transfer data.");
    faceit_hub_socket_port = CreateConVar("faceit_hub_socket_port", "1025", "Port used to transfer data.", .hasMin = true, .min = 1025.0);

    // Lobby
    faceit_hub_lobby_slots = CreateConVar("faceit_hub_lobby_slots", "5", "Provided amount of player slots per FACEIT lobby.", .hasMin = true, .min = 2.0);
    faceit_hub_lobby_invite_expiration = CreateConVar("faceit_hub_lobby_invite_expiration", "60", "Time in seconds that a FACEIT lobby invitation lasts for.");
    faceit_hub_lobby_create_message = CreateConVar("faceit_hub_lobby_create_message", "1", "Whether to send a global chat message once a new FACEIT lobby has created.", .hasMin = true, .hasMax = true, .max = 1.0);
    faceit_hub_lobby_chat_cooldown = CreateConVar("faceit_hub_lobby_chat_cooldown", "1.0", "Cooldown between FACEIT lobby chat messages. Seconds represented.", .hasMin = true, .min = 0.5);
    faceit_hub_lobby_create_cooldown = CreateConVar("faceit_hub_lobby_create_cooldown", "60.0", "Cooldown after creating new FACEIT lobby. Seconds represented.", .hasMin = true, .min = 15.0);

    AutoExecConfig();

    char socket_key[MAX_SOCKET_KEY_LENGTH];
    faceit_hub_socket_key.GetString(socket_key, sizeof(socket_key));

    if (!socket_key[0])
    {
        SetFailState("Please setup 'faceit_hub_socket_key' before using this plugin.");
    }
}

void RegisterCommands()
{
    RegConsoleCmd("sm_faceithub", Command_FACEITHub, "Access the FACEIT Hub main menu.");
    RegConsoleCmd("sm_faceit", Command_FACEITHub, "Access the FACEIT Hub main menu.");
    RegConsoleCmd("sm_hub", Command_FACEITHub, "Access the FACEIT Hub main menu.");

    RegConsoleCmd("sm_join", Command_Join, "Accepts a FACEIT lobby invitation.");
    RegConsoleCmd("sm_j", Command_Join, "Accepts a FACEIT lobby invitation.");

    RegConsoleCmd("sm_lobbychat", Command_LobbyChat, "Sends a message in your FACEIT lobby chat area.");
    RegConsoleCmd("sm_lc", Command_LobbyChat, "Sends a message in your FACEIT lobby chat area.");
}

Action Command_FACEITHub(int client, int argc)
{
    // Can't display a menu to the server console ._.
    if (!client)
    {
        ReplyToCommand(client, "This command is unavailable via the server console.");
        return Plugin_Handled;
    }

    Player player;
    if (!player.GetByIndex(client))
    {
        PrintToChat(client, " \x02Authentication failed, please contact the server administrator.\x01");
        return Plugin_Handled;
    }

    if (!player.faceit.IsLoaded())
    {
        PrintToChat(client, " \x02Seems like you do not own a FACEIT account ):\x01");
        return Plugin_Handled;
    }

    FaceitLobby faceit_lobby;
    if (player.GetFaceitLobby(faceit_lobby))
    {
        DisplayLobbyMenu(client, faceit_lobby);
    }
    else
    {
        DisplayInterfaceMenu(client);
    }

    return Plugin_Handled;
}

Action Command_Join(int client, int argc)
{
    if (!client)
    {
        ReplyToCommand(client, "This command is unavailable via the server console.");
        return Plugin_Handled;
    }

    Player player;
    if (!player.GetByIndex(client))
    {
        return Plugin_Handled;
    }

    if (!player.invitations.Length)
    {
        PrintToChat(client, " \x02There are no pending FACEIT lobby invitations!\x01");
        return Plugin_Handled;
    }

    if (player.invitations.Length > 1)
    {
        DisplayIncomeInvitationsMenu(client);
        return Plugin_Handled;
    }

    LobbyInvitation lobby_invitation;
    player.invitations.GetArray(0, lobby_invitation);

    FaceitLobby faceit_lobby;
    if (!faceit_lobby.GetByUUID(lobby_invitation.uuid))
    {
        faceit_lobby.InvitationExpire(player);

        PrintToChat(client, " \x02This lobby invitation is no longer valid.\x01");
        return Plugin_Handled;
    }

    faceit_lobby.JoinMember(player);

    return Plugin_Handled;
}

Action Command_LobbyChat(int client, int argc)
{
    if (!client)
    {
        ReplyToCommand(client, "This command is unavailable via the server console.");
        return Plugin_Handled;
    }

    int idx;
    Player player;

    if (!player.GetByIndex(client, idx))
    {
        return Plugin_Handled;
    }

    FaceitLobby faceit_lobby;
    if (!player.GetFaceitLobby(faceit_lobby))
    {
        PrintToChat(client, " \x02You are not in any FACEIT lobby!\x01");
        return Plugin_Handled;
    }

    float game_time = GetGameTime();
    if (player.cooldown.next_lobby_message > game_time)
    {
        return Plugin_Handled;
    }

    char message[512];
    GetCmdArgString(message, sizeof(message));

    if (!message[0])
    {
        PrintToChat(client, " \x02You cannot send an empty message!\x01");
        return Plugin_Handled;
    }

    // Update player cooldown.
    player.cooldown.next_lobby_message = game_time + faceit_hub_lobby_chat_cooldown.FloatValue;
    player.UpdateMyself(idx);

    // Send a lobby message!
    Format(message, sizeof(message), " \x0CLobby\x01 > %s%s\x01 : %s", g_ServerName, player.faceit.nickname, message);
    faceit_lobby.SendMessage(false, message);

    return Plugin_Handled;
}