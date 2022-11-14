#include <sourcemod>
#include <socket>
#include <bytebuffer>

#pragma semicolon 1
#pragma newdecls required

// String lengths declarations.
#define MAX_SOCKET_KEY_LENGTH 32

#define LISTEN_IP "0.0.0.0" // Listen to everything.
#define AUTHORIZE_HEADER 0x4E // 'N', listener header only.

enum struct SocketManager
{
    // All connected 'Socket's.
    ArrayList sockets;

    //============================================//
    void Init()
    {
        this.sockets = new ArrayList();
    }

    void AddSocket(Socket socket)
    {
        // Prevent duplicates.
        if (this.sockets.FindValue(socket) == -1)
        {
            this.sockets.Push(socket);
        }
    }

    void EraseSocket(Socket socket)
    {
        int idx = this.sockets.FindValue(socket);
        if (idx != -1)
        {
            this.sockets.Erase(idx);
        }
    }

    void Send(const char[] data, int size, Socket source)
    {
        Socket socket;

        for (int current_socket; current_socket < this.sockets.Length; current_socket++)
        {
            if ((socket = view_as<Socket>(this.sockets.Get(current_socket))) != source)
            {
                socket.Send(data, size);
            }
        }
    }

    bool IsSocketAuthorized(Socket socket)
    {
        return this.sockets.FindValue(socket) != -1;
    }
}

SocketManager g_SocketManager;

ConVar faceit_hub_socket_key;
ConVar faceit_hub_socket_port;

public Plugin myinfo =
{
    name = "FACEIT-Hub Listener",
    author = "KoNLiG",
    description = "Socket listener which acts as a bridge between all faceit hub servers.",
    version = "1.0.0",
    url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
    // Initialize convars.
    faceit_hub_socket_key = CreateConVar("faceit_hub_socket_key", "PASSWORD", "Key used to transfer data between sockets. Up to 32 characters.", FCVAR_HIDDEN);
    faceit_hub_socket_port = CreateConVar("faceit_hub_socket_port", "1025", "Port used to transfer data", .hasMin = true, .min = 1025.0);

    AutoExecConfig();

    char socket_key[MAX_SOCKET_KEY_LENGTH];
    faceit_hub_socket_key.GetString(socket_key, sizeof(socket_key));

    if (!socket_key[0])
    {
        SetFailState("Please setup 'faceit_hub_socket_key' before using this plugin.");
    }

    if (!SetupListenSocket())
    {
        SetFailState("Unable to setup listen socket.");
    }
    else
    {
        LogMessage("Server listening on %s:%d", LISTEN_IP, faceit_hub_socket_port.IntValue);
    }

    g_SocketManager.Init();
}

bool SetupListenSocket()
{
    Socket listen_socket = new Socket(SOCKET_TCP, OnListenSocketError);
    if (!listen_socket)
    {
        return false;
    }

    return listen_socket.Bind(LISTEN_IP, faceit_hub_socket_port.IntValue) && listen_socket.Listen(OnSocketIncoming);
}

void OnListenSocketError(Socket socket, const int errorType, const int errorNum, any arg)
{
    LogError("[ListenSocketError] %d (errno %d)", errorType, errorNum);
}

void OnSocketIncoming(Socket socket, Socket newSocket, const char[] remoteIP, int remotePort, any arg)
{
    newSocket.SetReceiveCallback(OnSocketReceive);
    newSocket.SetDisconnectCallback(OnSocketDisconnect);
    newSocket.SetErrorCallback(OnSocketError);
}

/*
 *  Request Base Format:
 *  1) Header
 * 	2) Socket key if header is 'AUTHORIZE_HEADER'
 *     otherwise it's the data.
 */
void OnSocketReceive(Socket socket, const char[] receiveData, const int dataSize, any arg)
{
    ByteBuffer byte_buffer = CreateByteBuffer(_, receiveData, dataSize);

    char header = byte_buffer.ReadByte();

    // Socket is already authorized, distirbute the recieved data!
    if (header != AUTHORIZE_HEADER && g_SocketManager.IsSocketAuthorized(socket))
    {
        g_SocketManager.Send(receiveData, dataSize, socket);

        byte_buffer.Close();

        return;
    }

    char socket_key[MAX_SOCKET_KEY_LENGTH];
    faceit_hub_socket_key.GetString(socket_key, sizeof(socket_key));

    char key[MAX_SOCKET_KEY_LENGTH];
    byte_buffer.ReadString(key, sizeof(key));

    if (StrEqual(socket_key, key))
    {
        g_SocketManager.AddSocket(socket);
    }

    byte_buffer.Close();
}

void OnSocketDisconnect(Socket socket, any arg)
{
    g_SocketManager.EraseSocket(socket);
}

void OnSocketError(Socket socket, const int errorType, const int errorNum, any arg)
{
    LogError("[SocketError] %d (errno %d)", errorType, errorNum);

    g_SocketManager.EraseSocket(socket);
}