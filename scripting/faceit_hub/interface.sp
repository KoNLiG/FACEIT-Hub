#assert defined COMPILING_FROM_MAIN

#define PREFIX_MENU "FACEIT-Hub | "

void DisplayInterfaceMenu(int client)
{
    Player player;
    if (!player.GetByIndex(client))
    {
        return;
    }

    Menu menu = new Menu(Handler_Interface);

    menu.SetTitle("%sInterface Menu:\n \n• Create a FACEIT lobby to team-up with\n   other players across all servers!\n ", PREFIX_MENU, g_FaceitLobbies.Length);

    char item_display[256];

    // Check for any cooldown.
    float game_time = GetGameTime();

    if (player.cooldown.next_lobby_create_time > game_time)
    {
        Format(item_display, sizeof(item_display), " [In cooldown for %.2fs]", player.cooldown.next_lobby_create_time - game_time);
    }

    Format(item_display, sizeof(item_display), "Create FACEIT Lobby%s\n \n◾ Found %d available lobby(s):",
    player.cooldown.next_lobby_create_time > game_time ? item_display : "", g_FaceitLobbies.Length);

    // FIXME: ... [player.cooldown.next_lobby_create_time <= game_time]
    menu.AddItem("", item_display, !player.GetFaceitLobby() ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    Player leader;
    FaceitLobby faceit_lobby;

    for (int current_lobby; current_lobby < g_FaceitLobbies.Length; current_lobby++)
    {
        g_FaceitLobbies.GetArray(current_lobby, faceit_lobby);

        faceit_lobby.members.GetArray(LEADER_MEMBER_IDX, leader);

        FormatEx(item_display, sizeof(item_display), "%s's Lobby [%d/%d]", leader.faceit.nickname, faceit_lobby.members.Length, faceit_hub_lobby_slots.IntValue);
        menu.AddItem(faceit_lobby.uuid, item_display);
    }

    menu.Display(client, 1);
}

int Handler_Interface(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1, selected_item = param2;

            switch (selected_item)
            {
                case 0:
                {
                    Player player;
                    if (!player.GetByIndex(client))
                    {
                        return 0;
                    }

                    if (player.GetFaceitLobby())
                    {
                        PrintToChat(client, " \x02You are already in a FACEIT lobby!\x01");
                        return 0;
                    }

                    player.CreateFaceitLobby();

                    FaceitLobby faceit_lobby;
                    if (player.GetFaceitLobby(faceit_lobby))
                    {
                        DisplayLobbyMenu(client, faceit_lobby);
                    }
                    else
                    {
                        DisplayInterfaceMenu(client);
                    }
                }
                default:
                {
                    // Check if the lobbies arraylist is empty
                    if (!g_FaceitLobbies.Length)
                    {
                        PrintToChat(client, " \x02There are no longer any available FACEIT lobbies!\x01");

                        DisplayInterfaceMenu(client);

                        return 0;
                    }

                    // int lobby_idx = selected_item - (menu.ItemCount - g_FaceitLobbies.Length);

                    char uuid[UUID_LENGTH];
                    menu.GetItem(selected_item, uuid, sizeof(uuid));

                    FaceitLobby faceit_lobby;
                    if (!faceit_lobby.GetByUUID(uuid))
                    {
                        PrintToChat(client, " \x02Sorry, this FACEIT lobby is no longer available.\x01");
                        return 0;
                    }

                    DisplayLobbyMenu(client, faceit_lobby);
                }
            }
        }
        case MenuAction_Cancel:
        {
            int client = param1, cancel_reason = param2;
            if (cancel_reason != MenuCancel_Timeout)
            {
                return 0;
            }

            Player player;
            if (!player.GetByIndex(client))
            {
                return 0;
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
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

enum
{
    LobbyMember,
    PendingPlayer
}

void DisplayLobbyMenu(int client, FaceitLobby faceit_lobby)
{
    Player player;
    if (!player.GetByIndex(client))
    {
        return;
    }

    int member_idx = faceit_lobby.FindMember(player);

    bool is_member = (member_idx != -1);
    bool is_leader = (member_idx == LEADER_MEMBER_IDX);

    Menu menu = new Menu(Handler_Lobby);

    char item_display[256], item_info[MAX_AUTHID_LENGTH];
    if (is_leader)
    {
        item_display = "My";
    }
    else
    {
        Player leader;
        faceit_lobby.members.GetArray(LEADER_MEMBER_IDX, leader);

        Format(item_display, sizeof(item_display), "%s's", leader.faceit.nickname);
    }

    menu.SetTitle("%s%s Lobby:\n \n◾ Information:\n    Avg. ˡᵛˡ%d\n    Avg. %dᴱᴸᴼ\n    %s\n ", PREFIX_MENU, item_display, faceit_lobby.GetAverageSkillLevel(), faceit_lobby.GetAverageElo(), faceit_lobby.IsPremiumLobby() ? "PREMIUM" : "̶P̶R̶E̶M̶I̶U̶M̶");

    // Pass the info (lobby identifier) as an invisible menu item.
    menu.AddItem(faceit_lobby.uuid, "", ITEMDRAW_IGNORE);

    if (is_leader)
    {
        Format(item_display, sizeof(item_display), "Invite online players [%d online]", g_Players.Length - 1); // - 1 to exclude ourself
        menu.AddItem("", item_display, g_Players.Length - 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

        int online_friends_count = player.faceit.GetOnlineFriendsCount();

        Format(item_display, sizeof(item_display), "Invite FACEIT friends [%d online]", online_friends_count);
        menu.AddItem("", item_display, online_friends_count ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    Format(item_display, sizeof(item_display), "%s\n \n◾ %d/%d Members:", is_leader ? "Disband" : is_member ? "Leave" : "Request To Join!", faceit_lobby.members.Length, faceit_hub_lobby_slots.IntValue);

    menu.AddItem("", item_display);

    char pending_join_requests[64];
    Format(pending_join_requests, sizeof(pending_join_requests), "\n \n◾ %d Pending join requests:", faceit_lobby.pending_players.Length);

    // Display all lobby members.
    Player member;
    for (int current_member; current_member < faceit_lobby.members.Length; current_member++)
    {
        faceit_lobby.members.GetArray(current_member, member);

        Format(item_display, sizeof(item_display), "[ˡᵛˡ%d] %s%s", member.faceit.skill_level, member.faceit.nickname, current_member == LEADER_MEMBER_IDX ? " (♕)" : "");

        if (faceit_lobby.pending_players.Length && current_member == faceit_lobby.members.Length - 1)
        {
            StrCat(item_display, sizeof(item_display), pending_join_requests);
        }

        FormatEx(item_info, sizeof(item_info), "%d:%s", LobbyMember, member.steamid64);
        menu.AddItem(item_info, item_display);
    }

    // Display all lobby pending join requests.
    for (int current_player; current_player < faceit_lobby.pending_players.Length; current_player++)
    {
        faceit_lobby.pending_players.GetArray(current_player, member);

        Format(item_display, sizeof(item_display), "[ˡᵛˡ%d] %s", member.faceit.skill_level, member.faceit.nickname);
        FormatEx(item_info, sizeof(item_info), "%d:%s", PendingPlayer, member.steamid64);
        menu.AddItem(item_info, item_display, is_leader ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }

    if (!is_member)
    {
        FixMenuGap(menu, 1);
        menu.ExitBackButton = true;
    }

    menu.Display(client, 1);
}

int Handler_Lobby(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1, selected_item = param2;

            Player player;
            if (!player.GetByIndex(client))
            {
                return 0;
            }

            // First menu item will always store the lobby uuid.
            char uuid[UUID_LENGTH];
            menu.GetItem(0, uuid, sizeof(uuid));

            FaceitLobby faceit_lobby;
            if (!faceit_lobby.GetByUUID(uuid))
            {
                PrintToChat(client, " \x02This FACEIT lobby just closed!\x01");
                return 0;
            }

            char item_display[64], item_info[MAX_AUTHID_LENGTH];
            menu.GetItem(selected_item, item_info, sizeof(item_info), _, item_display, sizeof(item_display));

            if (StrContains(item_display, "Invite online players") != -1)
            {
                if (!(g_Players.Length - 1))
                {
                    PrintToChat(client, " \x02There are no available players to invite!\x01");
                    return 0;
                }

                DisplayInvitationMenu(client, g_Players);
            }
            else if (StrContains(item_display, "Invite FACEIT friends") != -1)
            {
                if (!player.faceit.GetOnlineFriendsCount())
                {
                    PrintToChat(client, " \x02There are no available FACEIT friends to invite!\x01");
                    return 0;
                }

                DisplayInvitationMenu(client, player.faceit.GetOnlineFriends());
            }
            else if (StrContains(item_display, "Disband") != -1)
            {
                player.CloseFaceitLobby();

                PrintToChat(client, " \x04Successfully disbanded FACEIT lobby.\x01");

                DisplayInterfaceMenu(client);
            }
            else if (StrContains(item_display, "Leave") != -1)
            {
                char leader_auth[MAX_AUTHID_LENGTH];
                faceit_lobby.GetLeaderAuth(leader_auth);

                PrintToChatSeperators(client, " \x09You left the lobby.\x01");

                faceit_lobby.KickMember(player);
                faceit_lobby.SendMessage(_, " \x0B%s\x09 has left the lobby.\x01", player.faceit.nickname);
            }
            else if (StrContains(item_display, "Request To Join!") != -1)
            {
                if (player.GetFaceitLobby())
                {
                    PrintToChat(client, " \x02You cannot send a lobby join request while being in a lobby of yourself!.\x01");
                    return 0;
                }

                // Player is already invited - automatically let the join request go though.
                if (player.invitations.FindString(faceit_lobby.uuid) != -1)
                {
                    faceit_lobby.JoinMember(player);
                    return 0;
                }

                if (faceit_lobby.pending_players.FindString(player.steamid64) != -1)
                {
                    PrintToChat(client, " \x02There is already an ongoing join request to this lobby!\x01");
                    return 0;
                }

                player.SendLobbyJoinRequest(faceit_lobby);

                Player leader;
                faceit_lobby.members.GetArray(LEADER_MEMBER_IDX, leader);

                PrintToChat(client, " \x09Successfully sent a join request to \x0B%s's\x09 FACEIT lobby!\x01", leader.faceit.nickname);
            }
            else
            {
                char exploded_info[2][MAX_AUTHID_LENGTH];
                ExplodeString(item_info, ":", exploded_info, sizeof(exploded_info), sizeof(exploded_info[]));

                Player target;
                if (target.GetBySteamID64(exploded_info[1]) == -1)
                {
                    PrintToChat(client, " \x02This player is no longer online!\x01");
                    return 0;
                }

                if (exploded_info[0][0] == '0') // LobbyMember
                {
                    DisplayLobbyMemberMenu(client, target);
                }
                else if (exploded_info[0][0] == '1') // PendingPlayer
                {
                    if (faceit_lobby.pending_players.FindString(target.steamid64) == -1)
                    {
                        PrintToChat(client, " \x02This player is no longer interested in this lobby!\x01");
                        return 0;
                    }

                    faceit_lobby.JoinMember(target);
                }
            }
        }
        case MenuAction_Cancel:
        {
            int client = param1, cancel_reason = param2;
            if (cancel_reason != MenuCancel_Timeout)
            {
                if (cancel_reason == MenuCancel_ExitBack)
                {
                    DisplayInterfaceMenu(client);
                }

                return 0;
            }

            // First menu item will always store the lobby uuid.
            char uuid[UUID_LENGTH];
            menu.GetItem(0, uuid, sizeof(uuid));

            FaceitLobby faceit_lobby;
            if (!faceit_lobby.GetByUUID(uuid))
            {
                DisplayInterfaceMenu(client);

                PrintToChat(client, " \x02This FACEIT lobby just closed!\x01");

                return 0;
            }

            DisplayLobbyMenu(client, faceit_lobby);
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayLobbyMemberMenu(int client, Player member)
{
    Player player;
    if (!player.GetByIndex(client))
    {
        return;
    }

    bool is_leader;
    FaceitLobby faceit_lobby;
    player.GetFaceitLobby(faceit_lobby, is_leader);

    FaceitLobby member_faceit_lobby;
    if (!member.GetFaceitLobby(member_faceit_lobby))
    {
        return;
    }

    bool myself = (client == member.GetIndex());
    bool allowed_to_remove = !myself && is_leader && faceit_lobby.IsEqual(member_faceit_lobby);

    Menu menu = new Menu(Handler_LobbyMember);

    menu.SetTitle("%s Overviewing %s\n \n◾ ˡᵛˡ%d\n◾ %dᴱᴸᴼ\n◾ %s\n◾ %d friends (%d online)\n ",
        PREFIX_MENU,
        myself ? "Myself" : member.faceit.nickname,
        member.faceit.skill_level,
        member.faceit.elo,
        member.faceit.has_premium ? "PREMIUM" : "̶P̶R̶E̶M̶I̶U̶M̶",
        member.faceit.friends.Length,
        member.faceit.GetOnlineFriendsCount()
        );

    menu.AddItem(member.steamid64, "Remove From Lobby", allowed_to_remove ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    FixMenuGap(menu);
    menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_LobbyMember(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1;

            Player player;
            if (!player.GetByIndex(client))
            {
                return 0;
            }

            char target_auth[MAX_AUTHID_LENGTH];
            menu.GetItem(0, target_auth, sizeof(target_auth));

            Player member;
            if (member.GetBySteamID64(target_auth) == -1)
            {
                PrintToChat(client, " \x02This player is no longer online!\x01");
                return 0;
            }

            bool is_leader;
            FaceitLobby faceit_lobby;
            if (!player.GetFaceitLobby(faceit_lobby, is_leader))
            {
                PrintToChat(client, " \x02You are no longer in a FACEIT lobby!\x01");
                return 0;
            }

            FaceitLobby member_faceit_lobby;
            if (!member.GetFaceitLobby(member_faceit_lobby))
            {
                PrintToChat(client, " \x02This player is no longer in a FACEIT lobby!\x01");
                return 0;
            }

            bool allowed_to_remove = (client != member.GetIndex() && is_leader && faceit_lobby.IsEqual(member_faceit_lobby));
            if (!allowed_to_remove)
            {
                PrintToChat(client, " \x02You are not allowed to remove this player from this lobby!\x01");
                return 0;
            }

            faceit_lobby.KickMember(member, true);
            faceit_lobby.SendMessage(_, " \x0B%s\x09 has been removed from the lobby.", member.faceit.nickname);
        }
        case MenuAction_Cancel:
        {
            int client = param1, cancel_reason = param2;
            if (cancel_reason == MenuCancel_ExitBack)
            {
                Command_FACEITHub(client, 0);
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayInvitationMenu(int client, ArrayList players)
{
    Player player;
    if (!player.GetByIndex(client))
    {
        return;
    }

    Menu menu = new Menu(Handler_Invitation);

    menu.SetTitle("%sInvitation Menu:\n \n• Select a player to send an invitation to:\n ", PREFIX_MENU);

    char item_display[MAX_NAME_LENGTH];
    Player current_player;

    for (int current_player_idx; current_player_idx < players.Length; current_player_idx++)
    {
        players.GetArray(current_player_idx, current_player);

        if (current_player.IsEqual(player))
        {
            continue;
        }

        bool in_lobby = current_player.GetFaceitLobby();

        FormatEx(item_display, sizeof(item_display), "[ˡᵛˡ%d] %s (%dᴱᴸᴼ)%s", current_player.faceit.skill_level, current_player.faceit.nickname, current_player.faceit.elo, in_lobby ? " [IN LOBBY]" : "");
        menu.AddItem(current_player.steamid64, item_display, in_lobby ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }

    FixMenuGap(menu);
    menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_Invitation(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int client = param1, selected_item = param2;

            Player player;
            if (!player.GetByIndex(client))
            {
                return 0;
            }

            bool is_leader;
            FaceitLobby faceit_lobby;

            if (!player.GetFaceitLobby(faceit_lobby, is_leader) || !is_leader)
            {
                return 0;
            }

            char target_auth[MAX_AUTHID_LENGTH];
            menu.GetItem(selected_item, target_auth, sizeof(target_auth));

            Player target;
            if (target.GetBySteamID64(target_auth) == -1)
            {
                PrintToChat(client, " \x02This player is no longer online!\x01");
                return 0;
            }

            if (target.GetFaceitLobby())
            {
                PrintToChat(client, " \x02This player is already in a FACEIT lobby!\x01");
                return 0;
            }

            if (target.invitations.FindString(faceit_lobby.uuid) != -1)
            {
                PrintToChat(client, " \x02There is already a pending lobby invitation request for %s!\x01", target.faceit.nickname);
                return 0;
            }

            // Player has already requested to join, automatically accept them!
            if (faceit_lobby.pending_players.FindString(target.steamid64) != -1)
            {
                faceit_lobby.JoinMember(target);
                return 0;
            }

            player.InviteToLobby(target);

            faceit_lobby.SendMessage(_, " \x0B[ˡᵛˡ%d] %s\x09 invited \x0B[ˡᵛˡ%d] %s\x09 to the lobby!\x09 They have \x07%d\x09 seconds to accept.",
                player.faceit.skill_level, player.faceit.nickname, target.faceit.skill_level, target.faceit.nickname, faceit_hub_lobby_invite_expiration.IntValue
                );
        }
        case MenuAction_Cancel:
        {
            int client = param1, cancel_reason = param2;
            if (cancel_reason != MenuCancel_ExitBack)
            {
                return 0;
            }

            Player player;
            if (!player.GetByIndex(client))
            {
                return 0;
            }

            FaceitLobby faceit_lobby;
            if (!player.GetFaceitLobby(faceit_lobby))
            {
                DisplayInterfaceMenu(client);
                return 0;
            }

            DisplayLobbyMenu(client, faceit_lobby);
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayIncomeInvitationsMenu(int client)
{
    Player player;
    if (!player.GetByIndex(client))
    {
        return;
    }

    Menu menu = new Menu(Handler_IncomeInvitations);

    menu.SetTitle("%sInvitation List Menu:\n \n• It appears you have multiple incoming lobby invitations\n   select a lobby you would like to join:\n ", PREFIX_MENU);

    char item_display[MAX_NAME_LENGTH], leader_name[MAX_NAME_LENGTH];
    LobbyInvitation lobby_invitation;
    FaceitLobby faceit_lobby;

    for (int current_invitation; current_invitation < player.invitations.Length; current_invitation++)
    {
        player.invitations.GetArray(current_invitation, lobby_invitation);

        if (!faceit_lobby.GetByUUID(lobby_invitation.uuid))
        {
            continue;
        }

        faceit_lobby.GetLeaderNickname(leader_name);

        FormatEx(item_display, sizeof(item_display), "%s's Lobby", leader_name);
        menu.AddItem(faceit_lobby.uuid, item_display);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_IncomeInvitations(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1, selected_item = param2;

        Player player;
        if (!player.GetByIndex(client))
        {
            return 0;
        }

        char uuid[UUID_LENGTH];
        menu.GetItem(selected_item, uuid, sizeof(uuid));

        FaceitLobby faceit_lobby;
        if (!faceit_lobby.GetByUUID(uuid))
        {
            faceit_lobby.InvitationExpire(player);

            PrintToChat(client, " \x02This lobby invitation is no longer valid.\x01");
            return 0;
        }

        int idx = player.invitations.FindString(uuid);
        if (idx == -1)
        {
            PrintToChat(client, " \x02This lobby invitation has already expired.\x01");
            return 0;
        }

        faceit_lobby.JoinMember(player);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}