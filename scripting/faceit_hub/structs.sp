#assert defined COMPILING_FROM_MAIN

#define LEADER_MEMBER_IDX 0
#define UUID_LENGTH 8

ArrayList g_FaceitLobbies;

/* We certainly DON'T want to define it
 * as 'Player g_Players[MAXPLAYERS + 1]' since
 * it contains all cross server 'Player's.
 */
ArrayList g_Players;

// Represents a FACEIT lobby.
enum struct FaceitLobby
{
    // Unique lobby identifier.
    char uuid[UUID_LENGTH];

    // Contains all lobby members, 'Player'.
    // First element will always be the lobby leader.
    //
    // Amount of elements should not exceed 'faceit_hub_lobby_slots.IntValue'
    ArrayList members;

    // Pending join requests. 'Player'.
    ArrayList pending_players;

    //================================//
    void Init(Player leader, const char uuid[UUID_LENGTH])
    {
        strcopy(this.uuid, sizeof(FaceitLobby::uuid), uuid);

        this.members = new ArrayList(sizeof(Player));
        this.members.PushArray(leader);

        // Clear leader cache.
        leader.invitations.Clear();
        leader.ClearJoinRequests();

        this.pending_players = new ArrayList(sizeof(Player));

        g_FaceitLobbies.PushArray(this);
    }

    void Close(int idx)
    {
        delete this.members;
        delete this.pending_players;

        this.ClearIncomingInvitations();
        g_FaceitLobbies.Erase(idx);
    }

    bool GetByUUID(const char uuid[UUID_LENGTH], int &idx = -1)
    {
        if ((idx = g_FaceitLobbies.FindString(uuid)) == -1)
        {
            return false;
        }

        FaceitLobby faceit_lobby;
        g_FaceitLobbies.GetArray(idx, faceit_lobby);

        this = faceit_lobby;

        return true;
    }

    bool IsEqual(FaceitLobby other)
    {
        return StrEqual(this.uuid, other.uuid);
    }

    bool JoinMember(Player player)
    {
        // Restrict lobby slots.
        if (this.members.Length >= faceit_hub_lobby_slots.IntValue)
        {
            return false;
        }

        this.SendMessage(_, " \x0B%s\x09 joined the lobby.\x01", player.faceit.nickname);

        SendJoinPacket(this.uuid, player.steamid64);

        return true;
    }

    void KickMember(Player player, bool removed = false)
    {
        SendJoinPacket(this.uuid, player.steamid64, false, removed);
    }

    void SendMessage(bool add_seperators = true, const char[] format, any...)
    {
        char message[256];
        VFormat(message, sizeof(message), format, 4);

        if (add_seperators)
        {
            SendMessagePacket(this.uuid, SEPERATOR);
        }

        SendMessagePacket(this.uuid, message);

        if (add_seperators)
        {
            SendMessagePacket(this.uuid, SEPERATOR);
        }
    }

    void InvitationExpire(Player player)
    {
        char leader_auth[MAX_AUTHID_LENGTH];
        this.GetLeaderAuth(leader_auth);

        SendInvitePacket(leader_auth, player.steamid64, false);

        this.SendMessage(_, " \x09The lobby invite to \x0B%s\x09 has expired.\x01", player.faceit.nickname);
    }

    void ClearIncomingInvitations()
    {
        int my_idx = g_FaceitLobbies.FindString(this.uuid);
        if (my_idx == -1)
        {
            return;
        }

        Player player;
        LobbyInvitation lobby_invitation;

        for (int current_player; current_player < g_Players.Length; current_player++)
        {
            g_Players.GetArray(current_player, player);

            for (int current_invitation, idx; current_invitation < player.invitations.Length; current_invitation++)
            {
                player.invitations.GetArray(current_invitation, lobby_invitation);

                if ((idx = g_FaceitLobbies.FindString(lobby_invitation.uuid)) != -1 && idx == my_idx)
                {
                    player.invitations.Erase(current_invitation--);
                }
            }
        }
    }

    void GetLeaderAuth(char buffer[MAX_AUTHID_LENGTH])
    {
        this.members.GetString(LEADER_MEMBER_IDX, buffer, sizeof(buffer));
    }

    void GetLeaderNickname(char buffer[MAX_NAME_LENGTH])
    {
        Player leader;

        this.members.GetArray(LEADER_MEMBER_IDX, leader);

        strcopy(buffer, sizeof(buffer), leader.faceit.nickname);
    }

    int FindMember(Player player)
    {
        Player current_player;
        for (int current_member; current_member < this.members.Length; current_member++)
        {
            this.members.GetArray(current_member, current_player);

            if (player.IsEqual(current_player))
            {
                return current_member;
            }
        }

        return -1;
    }

    int GetAverageElo()
    {
        int sum_elo;

        Player member;
        for (int current_member; current_member < this.members.Length; current_member++)
        {
            this.members.GetArray(current_member, member);

            sum_elo += member.faceit.elo;
        }

        return sum_elo / this.members.Length;
    }

    int GetAverageSkillLevel()
    {
        int sum_skill_level;

        Player member;
        for (int current_member; current_member < this.members.Length; current_member++)
        {
            this.members.GetArray(current_member, member);

            sum_skill_level += member.faceit.skill_level;
        }

        return sum_skill_level / this.members.Length;
    }

    bool IsPremiumLobby()
    {
        Player member;
        for (int current_member; current_member < this.members.Length; current_member++)
        {
            this.members.GetArray(current_member, member);

            if (!member.faceit.has_premium)
            {
                return false;
            }
        }

        return true;
    }
}

enum struct Faceit
{
    char nickname[MAX_NAME_LENGTH];

    char player_id[MAX_PLAYER_ID_LENGTH];

    // Stores all |this| friends player_id's.
    ArrayList friends;

    int skill_level;

    int elo;

    bool has_premium;

    //================================//
    void Init(FaceitPlayer faceit_player)
    {
        faceit_player.GetNickname(this.nickname, sizeof(Faceit::nickname));

        faceit_player.GetPlayerId(this.player_id, sizeof(Faceit::player_id));

        this.friends = new ArrayList(ByteCountToCells(MAX_PLAYER_ID_LENGTH));

        // Load all player friends into 'this.friends'.
        Handle friends_ids = json_object_get(faceit_player, "friends_ids");
        char friend_id[MAX_PLAYER_ID_LENGTH];

        for (int current_friend; current_friend < json_array_size(friends_ids); current_friend++)
        {
            if (json_array_get_string(friends_ids, current_friend, friend_id, sizeof(friend_id)) != -1)
            {
                this.friends.PushString(friend_id);
            }
        }

        FaceitGame recent_csgo_game = view_as<FaceitGame>(view_as<FaceitGames>(faceit_player.GetGames()).GetCSGO());

        this.skill_level = recent_csgo_game.skillLevel;
        this.elo = recent_csgo_game.faceitElo;

        Handle memberships = json_object_get(faceit_player, "memberships");
        if (memberships)
        {
            char membership[16];
            json_array_get_string(memberships, 0, membership, sizeof(membership));

            this.has_premium = !StrEqual(membership, "free");
        }
    }

    void Close()
    {
        this.nickname[0] = '\0';
        this.skill_level = 0;
        this.elo = 0;

        delete this.friends;
    }

    bool IsLoaded()
    {
        return this.nickname[0] != '\0';
    }

    // Returns an arraylist which contains all |this| player
    // online friends. ('Player' instances)
    ArrayList GetOnlineFriends()
    {
        ArrayList online_friends = new ArrayList(sizeof(Player));

        Player player;
        for (int current_player; current_player < g_Players.Length; current_player++)
        {
            g_Players.GetArray(current_player, player);

            if (this.friends.FindString(player.faceit.player_id) != -1)
            {
                online_friends.PushArray(player);
            }
        }

        return online_friends;
    }

    int GetOnlineFriendsCount()
    {
        ArrayList online_friends = this.GetOnlineFriends();

        int count = online_friends.Length;

        delete online_friends;

        return count;
    }
}

// Local relevant data, no need to sync them between
// servers since they're associating with the player itself.
enum struct Cooldown
{
    // Next time this player could open a new FACEIT lobby. Game time represented.
    float next_lobby_create_time;

    // Next time this player could send a lobby chat message. Game time represented.
    float next_lobby_message;
    //================================//
    // Must call in 'OnMapStart()'
    void Reset()
    {
        this.next_lobby_create_time = 0.0;
        this.next_lobby_message = 0.0;
    }
}

enum struct Player
{
    char steamid64[MAX_AUTHID_LENGTH];

    Faceit faceit;

    // All lobby invitations sent in the last 60 seconds (faceit_hub_lobby_invite_expiration.IntValue)
    ArrayList invitations;

    Cooldown cooldown;

    //================================//
    void Init(const char[] auth)
    {
        strcopy(this.steamid64, sizeof(Player::steamid64), auth);

        Faceit_GetPlayer(OnFaceitPlayerInitialized, .game = "csgo", .gamePlayerId = this.steamid64);

        this.invitations = new ArrayList(sizeof(LobbyInvitation));
    }

    void Close()
    {
        bool is_leader;
        FaceitLobby faceit_lobby;

        if (this.GetFaceitLobby(faceit_lobby, is_leader))
        {
            if (is_leader)
            {
                faceit_lobby.SendMessage(_, " \x07The lobby was disbanded because the lobby leader left!\x01");

                this.CloseFaceitLobby();
            }
            else
            {
                faceit_lobby.KickMember(this);

                faceit_lobby.SendMessage(_, " \x0B%s\x07 left the server, therefore they were removed from the party.\x01", this.faceit.nickname);
            }
        }

        this.invitations.Clear();
        this.ClearJoinRequests();

        this.steamid64[0] = '\0';

        this.faceit.Close();

        delete this.invitations;

        this.cooldown.Reset();
    }

    bool IsEqual(Player other)
    {
        return StrEqual(this.steamid64, other.steamid64);
    }

    // Init functions.
    int GetBySteamID64(const char[] auth, bool copyback = true)
    {
        Player player;

        for (int current_player; current_player < g_Players.Length; current_player++)
        {
            g_Players.GetArray(current_player, player);

            if (StrEqual(player.steamid64, auth))
            {
                if (copyback)
                {
                    this = player;
                }

                return current_player;
            }
        }

        return -1;
    }

    bool GetByIndex(int client, int &idx = -1)
    {
        Player player;

        for (int current_player; current_player < g_Players.Length; current_player++)
        {
            g_Players.GetArray(current_player, player);

            if (player.GetIndex() == client)
            {
                this = player;
                idx = current_player;
                return true;
            }
        }

        return false;
    }

    void UpdateMyself(int idx = -1)
    {
        if (idx == -1 && (idx = this.GetBySteamID64(this.steamid64, false)) == -1)
        {
            return;
        }

        g_Players.SetArray(idx, this);

        FaceitLobby faceit_lobby;
        if (this.GetFaceitLobby(faceit_lobby) && (idx = faceit_lobby.FindMember(this)) != -1)
        {
            faceit_lobby.members.SetArray(idx, this);
        }
    }

    bool IsLocal(int &client = 0)
    {
        return (client = this.GetIndex()) != 0;
    }

    int GetIndex()
    {
        return GetPlayerBySteamID64(this.steamid64);
    }

    void CreateFaceitLobby()
    {
        this.cooldown.next_lobby_create_time = GetGameTime() + faceit_hub_lobby_create_cooldown.FloatValue;

        this.UpdateMyself();

        char new_uuid[UUID_LENGTH];
        GenerateLobbyUUID(new_uuid);

        SendLobbyCreatePacket(new_uuid, this.steamid64);
    }

    void CloseFaceitLobby()
    {
        FaceitLobby faceit_lobby;
        if (this.GetFaceitLobby(faceit_lobby))
        {
            SendLobbyCreatePacket(faceit_lobby.uuid, this.steamid64, false);
        }
    }

    bool GetFaceitLobby(FaceitLobby faceit_lobby = {  }, bool &is_leader = false)
    {
        for (int current_lobby, idx; current_lobby < g_FaceitLobbies.Length; current_lobby++)
        {
            g_FaceitLobbies.GetArray(current_lobby, faceit_lobby);

            if ((idx = faceit_lobby.FindMember(this)) != -1)
            {
                is_leader = (idx == LEADER_MEMBER_IDX);

                return true;
            }
        }

        return false;
    }

    void InviteToLobby(Player invitee)
    {
        if (invitee.ProcessInvite(this))
        {
            return;
        }

        SendInvitePacket(this.steamid64, invitee.steamid64);

        FaceitLobby faceit_lobby;
        if (this.GetFaceitLobby(faceit_lobby))
        {
            invitee.AppendFaceitInvitation(faceit_lobby);
        }
    }

    bool ProcessInvite(Player invitor)
    {
        int client;
        if (!this.IsLocal(client))
        {
            return false;
        }

        PrintToChatSeperators(client,
            " \x0B[ˡᵛˡ%d] %s\x09 has invited you to join their FACEIT lobby!\x01"...LINE_BREAK...
            "\x09You have \x07%d\x09 seconds to accept. \x10Type /j to join!\x01",
            invitor.faceit.skill_level, invitor.faceit.nickname, faceit_hub_lobby_invite_expiration.IntValue
            );

        DataPack dp;
        CreateDataTimer(faceit_hub_lobby_invite_expiration.FloatValue, Timer_InvitationExpire, dp);
        dp.WriteCell(GetClientUserId(client));
        dp.WriteString(invitor.steamid64);

        FaceitLobby faceit_lobby;
        if (invitor.GetFaceitLobby(faceit_lobby))
        {
            this.AppendFaceitInvitation(faceit_lobby);
        }

        return true;
    }

    void AppendFaceitInvitation(FaceitLobby dest)
    {
        LobbyInvitation new_lobby_invitation;
        new_lobby_invitation.Init(dest);

        this.invitations.PushArray(new_lobby_invitation);
    }

    void SendLobbyJoinRequest(FaceitLobby faceit_lobby)
    {
        SendJoinRequestPacket(faceit_lobby.uuid, this.steamid64);
    }

    void ClearJoinRequests()
    {
        FaceitLobby faceit_lobby;

        for (int current_lobby, idx; current_lobby < g_FaceitLobbies.Length; current_lobby++)
        {
            g_FaceitLobbies.GetArray(current_lobby, faceit_lobby);

            if ((idx = faceit_lobby.pending_players.FindString(this.steamid64)) != -1)
            {
                faceit_lobby.pending_players.Erase(idx);
            }
        }
    }
}

enum struct LobbyInvitation
{
    // UUID of the destination lobby.
    char uuid[UUID_LENGTH];

    // Invitation time. Represented by unix time.
    int time;
    //================================//
    void Init(FaceitLobby faceit_lobby)
    {
        strcopy(this.uuid, sizeof(LobbyInvitation::uuid), faceit_lobby.uuid);
        this.time = GetTime();
    }

    void ResetTime()
    {
        this.time = 0;
    }
}

void InitializeGlobals()
{
    g_FaceitLobbies = new ArrayList(sizeof(FaceitLobby));
    g_Players = new ArrayList(sizeof(Player));
}

void OnFaceitPlayerInitialized(bool valid, Handle hPlayer)
{
    if (!valid)
    {
        return;
    }

    FaceitPlayer faceit_player = view_as<FaceitPlayer>(hPlayer);

    char auth[MAX_AUTHID_LENGTH];
    faceit_player.GetSteamId64(auth, sizeof(auth));

    int idx;
    Player player;

    if ((idx = player.GetBySteamID64(auth)) == -1)
    {
        return;
    }

    player.faceit.Init(faceit_player);

    player.UpdateMyself(idx);
}

int GetPlayerBySteamID64(const char[] auth)
{
    char current_auth[MAX_AUTHID_LENGTH];
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client)
             && GetClientAuthId(current_client, AuthId_SteamID64, current_auth, sizeof(current_auth))
             && StrEqual(current_auth, auth))
        {
            return current_client;
        }
    }

    return 0;
}

Action Timer_InvitationExpire(Handle timer, DataPack dp)
{
    dp.Reset();

    int client = GetClientOfUserId(dp.ReadCell())
    if (!client)
    {
        return Plugin_Continue;
    }

    // Invitor SteamID64
    char auth[MAX_AUTHID_LENGTH];
    dp.ReadString(auth, sizeof(auth));

    Player player, invitor;
    if (!player.GetByIndex(client) || invitor.GetBySteamID64(auth) == -1)
    {
        return Plugin_Continue;
    }

    FaceitLobby faceit_lobby;
    if (invitor.GetFaceitLobby(faceit_lobby) && !player.GetFaceitLobby() && player.invitations.FindString(faceit_lobby.uuid) != -1)
    {
        PrintToChatSeperators(client, " \x09The FACEIT lobby invite from \x0B%s\x09 has expired.\x01", invitor.faceit.nickname);

        faceit_lobby.InvitationExpire(player);
    }

    return Plugin_Continue;
}

int GetRandomIntEx(int min, int max)
{
    int random = GetURandomInt();
    if (!random)
    {
        random++;
    }

    return RoundToCeil(float(random) / (float(cellmax) / float(max - min + 1))) + min - 1;
}

void GetRandomString(char[] buffer, int maxlength, int length, const char[] chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789")
{
    if (length >= maxlength)
    {
        length = maxlength;
    }

    for (int i; i < length; i++)
    {
        Format(buffer, maxlength, "%s%c", buffer, chars[GetRandomIntEx(0, strlen(chars) - 1)]);
    }
}

void GenerateLobbyUUID(char uuid[UUID_LENGTH])
{
    do
    {
        GetRandomString(uuid, sizeof(uuid), UUID_LENGTH);
    } while (g_FaceitLobbies.FindString(uuid) != -1);
}