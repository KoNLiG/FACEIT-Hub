#assert defined COMPILING_FROM_MAIN

#define AUTHORIZE_HEADER 0x4E // 'N', listener header only.

#define MESSAGE_HEADER 0x4D // 'M'
#define SYNC_HEADER 0x56 // 'V'
#define LOBBY_JOIN_REQ_HEADER 0x52 // 'R'

// "Togglable headers"
#define PLAYER_CONNECT_HEADER 0x43 // 'C'
#define LOBBY_CREATE_HEADER 0x4C // 'L'
#define LOBBY_JOIN_HEADER 0x4A // 'J'
#define LOBBY_INVITE_HEADER 0x49 // 'I'

Socket g_Socket;

void SetupClientSocket()
{
    delete g_Socket;

    if (!(g_Socket = new Socket(SOCKET_TCP, OnSocketError)))
    {
        return;
    }

    char ipv4[MAX_IPV4_LENGTH];
    faceit_hub_socket_ip.GetString(ipv4, sizeof(ipv4));

    g_Socket.Connect(OnSocketConnect, OnSocketReceive, OnSocketDisconnect, ipv4, faceit_hub_socket_port.IntValue);
}

// Socket handling.
void OnSocketConnect(Socket socket, any arg)
{
    // Authorize myself against the listen server.
    SendAuthorizePacket();

    if (g_Lateload)
    {
        SendSyncPacket();
    }

    PrintToChatAll(" \x04[OnSocketConnect]\x01");

    LogMessage("Sucessfully connected to listen server.");
}

void OnSocketReceive(Socket socket, const char[] receiveData, const int dataSize, any arg)
{
    ByteBuffer byte_buffer = CreateByteBuffer(_, receiveData, dataSize);

    char header = byte_buffer.ReadByte();
    switch (header)
    {
        case MESSAGE_HEADER:
        {
            ProcessMessagePacket(byte_buffer);
        }
        case PLAYER_CONNECT_HEADER:
        {
            ProcessConnectPacket(byte_buffer);
        }
        case SYNC_HEADER:
        {
            ProcessSyncPacket();
        }
        case LOBBY_CREATE_HEADER:
        {
            ProcessLobbyCreatePacket(byte_buffer);
        }
        case LOBBY_JOIN_HEADER:
        {
            ProcessJoinPacket(byte_buffer);
        }
        case LOBBY_INVITE_HEADER:
        {
            ProcessInvitePacket(byte_buffer);
        }
        case LOBBY_JOIN_REQ_HEADER:
        {
            ProcessJoinRequestPacket(byte_buffer);
        }
    }

    byte_buffer.Close();

    if (g_Lateload)
    {
        CreateTimer(1.0, Tiemr_DisableLateloadMode);
    }
}

Action Tiemr_DisableLateloadMode(Handle timer)
{
    g_Lateload = false;

    return Plugin_Continue;
}

//==================================== [Packet Processing] ====================================//

/*
 *  Format:
 * 	1) Lobby UUID, or null terminated string if this is a global message
 * 	2) Raw printed message
 */
void ProcessMessagePacket(ByteBuffer byte_buffer)
{
    char uuid[UUID_LENGTH];
    byte_buffer.ReadString(uuid, sizeof(uuid));

    char message[256];
    byte_buffer.ReadString(message, sizeof(message));

    // This is a global message.
    if (!uuid[0])
    {
        PrintToChatAll("%s", message);
        return;
    }

    FaceitLobby faceit_lobby;
    if (!faceit_lobby.GetByUUID(uuid))
    {
        return;
    }

    Player member;
    for (int current_member, client; current_member < faceit_lobby.members.Length; current_member++)
    {
        faceit_lobby.members.GetArray(current_member, member);

        PrintToChatAll("[ProcessMessagePacket] %s", member.faceit.nickname);

        if (member.IsLocal(client))
        {
            PrintToChat(client, "%s", message);
        }
    }
}

/*
 *  Format:
 * 	1) SteamID64 of lobby leader
 *  2) Boolean which determines whether we should connect/disconnect the provided player
 *  3) Boolean which determines about lateload
 */
void ProcessConnectPacket(ByteBuffer byte_buffer)
{
    char steamid64[MAX_AUTHID_LENGTH];
    byte_buffer.ReadString(steamid64, sizeof(steamid64));

    bool connect = byte_buffer.ReadByte() != 0;
    bool late_load = byte_buffer.ReadByte() != 0;

    if (!g_Lateload && late_load)
    {
        return;
    }

    if (connect)
    {
        Player new_player;
        if (new_player.GetBySteamID64(steamid64) != -1)
        {
            return;
        }

        new_player.Init(steamid64);

        g_Players.PushArray(new_player);
    }
    else
    {
        int idx;
        Player old_player;

        if ((idx = old_player.GetBySteamID64(steamid64)) != -1)
        {
            old_player.Close();
            old_player.EraseMyself(idx);
        }
    }
}

/*
 *  Empty Format
 */
void ProcessSyncPacket()
{
    // Sync players.
    char auth[MAX_AUTHID_LENGTH];
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && GetClientAuthId(current_client, AuthId_SteamID64, auth, sizeof(auth)))
        {
            OnPlayerConnect(auth);
        }
    }

    CreateTimer(0.1, SendFaceitLobbies);
}

/*
 *  Format:
 *  1) Lobby UUID
 *  2) Creator SteamID64
 *  3) Boolean which determines whether we should create/remove the provided lobby
 *  4) Boolean which determines about lateload
 */
void ProcessLobbyCreatePacket(ByteBuffer byte_buffer)
{
    char uuid[UUID_LENGTH];
    byte_buffer.ReadString(uuid, sizeof(uuid));

    char steamid64[MAX_AUTHID_LENGTH];
    byte_buffer.ReadString(steamid64, sizeof(steamid64));

    Player leader;
    if (leader.GetBySteamID64(steamid64) == -1)
    {
        return;
    }

    bool create = byte_buffer.ReadByte() != 0;
    bool late_load = byte_buffer.ReadByte() != 0;

    if (!g_Lateload && late_load)
    {
        return;
    }

    if (create)
    {
        FaceitLobby new_faceit_lobby;
        new_faceit_lobby.Init(leader, uuid);

        if (faceit_hub_lobby_create_message.BoolValue)
        {
            PrintToChatAll(" \x03[ˡᵛˡ%d] %s\x09 just opened a FACEIT lobby. Type \x10/faceithub\x09 to hop in!\x01", leader.faceit.skill_level, leader.faceit.nickname);
        }
    }
    else
    {
        int idx;
        FaceitLobby faceit_lobby;

        if (faceit_lobby.GetByUUID(uuid, idx))
        {
            faceit_lobby.Close(idx);
        }
    }
}

/*
 *  Format:
 * 	1) Lobby UUID
 *  2) SteamID64 of joining/leaving player
 *  3) Boolean which determines whether this player is joining or leaving the provided lobby
 *  3) Boolean which determines whether this player got removed
 *  4) Boolean which determines lateload
 */
void ProcessJoinPacket(ByteBuffer byte_buffer)
{
    char uuid[UUID_LENGTH];
    byte_buffer.ReadString(uuid, sizeof(uuid));

    FaceitLobby faceit_lobby;
    if (!faceit_lobby.GetByUUID(uuid))
    {
        return;
    }

    char steamid64[MAX_AUTHID_LENGTH];
    byte_buffer.ReadString(steamid64, sizeof(steamid64));

    Player player;
    if (player.GetBySteamID64(steamid64) == -1)
    {
        return;
    }

    bool join = byte_buffer.ReadByte() != 0;
    bool removed = byte_buffer.ReadByte() != 0;
    bool late_load = byte_buffer.ReadByte() != 0;

    if (!g_Lateload && late_load)
    {
        return;
    }

    if (join)
    {
        faceit_lobby.members.PushArray(player);

        player.invitations.Clear();
        player.ClearJoinRequests();

        int client;
        if (player.IsLocal(client))
        {
            Player leader;
            faceit_lobby.members.GetArray(LEADER_MEMBER_IDX, leader);

            PrintToChatSeperators(client, " \x09You have joined \x0B%s\x09 lobby!\x01", leader.faceit.nickname);
        }
    }
    else
    {
        int idx = faceit_lobby.members.FindString(player.steamid64);
        if (idx != -1)
        {
            faceit_lobby.members.Erase(idx);
        }

        if (removed)
        {
            int client;
            if (player.IsLocal(client))
            {
                Player leader;
                faceit_lobby.members.GetArray(LEADER_MEMBER_IDX, leader);

                PrintToChatSeperators(client, " \x09You have been kicked from the lobby by \x0B%s\x01", leader.faceit.nickname);
            }
        }
    }
}

/*
 *  Format:
 * 	1) SteamID64 of lobby leader
 *  2) SteamID64 of invitee
 *  3) Whether this is an invitation packet, or an expired invitation
 */
void ProcessInvitePacket(ByteBuffer byte_buffer)
{
    char leader_steamid64[MAX_AUTHID_LENGTH];
    byte_buffer.ReadString(leader_steamid64, sizeof(leader_steamid64));

    Player leader;
    if (leader.GetBySteamID64(leader_steamid64) == -1)
    {
        return;
    }

    char steamid64[MAX_AUTHID_LENGTH];
    byte_buffer.ReadString(steamid64, sizeof(steamid64));

    Player player;
    if (player.GetBySteamID64(steamid64) == -1)
    {
        return;
    }

    bool invitation = byte_buffer.ReadByte() != 0;

    if (invitation)
    {
        player.ProcessInvite(leader);
    }
    else
    {
        FaceitLobby faceit_lobby;
        if (!leader.GetFaceitLobby(faceit_lobby))
        {
            return;
        }

        int idx = player.invitations.FindString(faceit_lobby.uuid);
        if (idx != -1)
        {
            player.invitations.Erase(idx);
        }
    }
}

/*
 *  Format:
 * 	1) Lobby UUID
 *  2) SteamID64 of the requester
 */
void ProcessJoinRequestPacket(ByteBuffer byte_buffer)
{
    char uuid[UUID_LENGTH];
    byte_buffer.ReadString(uuid, sizeof(uuid));

    FaceitLobby faceit_lobby;
    if (!faceit_lobby.GetByUUID(uuid))
    {
        return;
    }

    char steamid64[MAX_AUTHID_LENGTH];
    byte_buffer.ReadString(steamid64, sizeof(steamid64));

    Player player;
    if (player.GetBySteamID64(steamid64) == -1)
    {
        return;
    }

    faceit_lobby.pending_players.PushArray(player);

    Player leader;
    faceit_lobby.members.GetArray(LEADER_MEMBER_IDX, leader);

    int client;
    if (leader.IsLocal(client))
    {
        PrintToChat(client, " \x0CLobby\x01 > \x09There is a pending join request from \x0B%s\x09!\x01", player.faceit.nickname);
    }
}

//==================================== [Socket Connection Maintain] ====================================//

void OnSocketError(Socket socket, const int errorType, const int errorNum, any arg)
{
    delete g_Socket;

    ThrowError("[OnSocketError] errorType: %d, errorNum: %d", errorType, errorNum);
}

void OnSocketDisconnect(Socket socket, any arg)
{
    delete g_Socket;

    CreateTimer(faceit_hub_socket_reconnect_interval.FloatValue, Timer_ResetupMasterSocket, .flags = TIMER_REPEAT);
}

Action Timer_ResetupMasterSocket(Handle timer)
{
    // No need to reconnect if we're already connected.
    if (g_Socket && g_Socket.Connected)
    {
        return Plugin_Stop;
    }

    SetupClientSocket();

    return Plugin_Continue;
}

//==================================== [Packet Wrappers] ====================================//

void SendAuthorizePacket()
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(AUTHORIZE_HEADER);

    char socket_key[MAX_SOCKET_KEY_LENGTH];
    faceit_hub_socket_key.GetString(socket_key, sizeof(socket_key));

    byte_buffer.WriteString(socket_key);

    TransferPacket(byte_buffer);
}

void SendPlayerConnectPacket(const char[] steamid64, bool connect = true, bool late_load = false)
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(PLAYER_CONNECT_HEADER);

    byte_buffer.WriteString(steamid64);
    byte_buffer.WriteByte(connect);
    byte_buffer.WriteByte(late_load);

    TransferPacket(byte_buffer);
}

void SendSyncPacket()
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(SYNC_HEADER);

    TransferPacket(byte_buffer);
}

// FIXME: Broken pipe temp fix
Action SendFaceitLobbies(Handle timer)
{
    Player player;
    FaceitLobby faceit_lobby;

    for (int current_player; current_player < g_Players.Length; current_player++)
    {
        g_Players.GetArray(current_player, player);

        bool is_leader;
        if (!player.GetFaceitLobby(faceit_lobby, is_leader))
        {
            continue;
        }

        if (is_leader)
        {
            SendLobbyCreatePacket(faceit_lobby.uuid, player.steamid64, .late_load = true);
        }
        else
        {
            SendJoinPacket(faceit_lobby.uuid, player.steamid64, .late_load = true);
        }
    }

    return Plugin_Continue;
}

void SendLobbyCreatePacket(const char uuid[UUID_LENGTH], const char[] steamid64, bool create = true, bool late_load = false)
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(LOBBY_CREATE_HEADER);

    byte_buffer.WriteString(uuid);
    byte_buffer.WriteString(steamid64);
    byte_buffer.WriteByte(create);
    byte_buffer.WriteByte(late_load);

    TransferPacket(byte_buffer);
}

void SendJoinPacket(const char uuid[UUID_LENGTH], const char[] steamid64, bool join = true, bool removed = false, bool late_load = false)
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(LOBBY_JOIN_HEADER);

    byte_buffer.WriteString(uuid);
    byte_buffer.WriteString(steamid64);
    byte_buffer.WriteByte(join);
    byte_buffer.WriteByte(removed);
    byte_buffer.WriteByte(late_load);

    TransferPacket(byte_buffer);
}

void SendInvitePacket(const char[] leader_steamid64, const char[] steamid64, bool invitation = true)
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(LOBBY_INVITE_HEADER);

    byte_buffer.WriteString(leader_steamid64);
    byte_buffer.WriteString(steamid64);
    byte_buffer.WriteByte(invitation);

    TransferPacket(byte_buffer);
}

void SendMessagePacket(const char[] steamid64, const char[] message)
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(MESSAGE_HEADER);

    byte_buffer.WriteString(steamid64);
    byte_buffer.WriteString(message);

    TransferPacket(byte_buffer);
}

void SendJoinRequestPacket(const char uuid[UUID_LENGTH], const char[] steamid64)
{
    ByteBuffer byte_buffer = CreateByteBuffer();

    byte_buffer.WriteByte(LOBBY_JOIN_REQ_HEADER);

    byte_buffer.WriteString(uuid);
    byte_buffer.WriteString(steamid64);

    TransferPacket(byte_buffer);
}

void TransferPacket(ByteBuffer byte_buffer)
{
    int size = byte_buffer.Cursor;
    char[] data = new char[size];

    byte_buffer.Dump(data, size);
    byte_buffer.Close();

    // Locally trigger the processing procedure of this packet,
    // to avoid unnecessary delays.
    OnSocketReceive(g_Socket, data, size, 0);

    // Send packet to the listen server.
    g_Socket.Send(data, size);
}