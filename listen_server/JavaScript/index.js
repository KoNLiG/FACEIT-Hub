var net = require('net');
const config = require("./config.json");

class SocketManager
{
    sockets = [];

    constructor()
    {
        this.sockets = [];
    }

    AddSocket(socket)
    {
        // Don't push duplicates.
        if (this.sockets.indexOf(socket) == -1)
        {
            this.sockets.push(socket);
        }
    }

    EraseSocket(socket)
    {
        var idx = this.sockets.indexOf(socket);
        if (idx != -1)
        {
            this.sockets.splice(idx, 1);
        }
    }

    Send(sender ,data)
    {
            this.sockets.forEach(socket => {
            if(socket!=sender)
                socket.write(data);
            });
    }

    IsSocketAuthorized(socket)
    {
        return (this.sockets.indexOf(socket) != -1);
    }
}

const socket_manager = new SocketManager({});

var host = '0.0.0.0';
var port = config.port;

net.createServer(sock => {
    console.log(`connected: ${sock.remoteAddress}:${sock.remotePort}`);

    sock.on('data', (data) => {
        console.log(`${sock.remoteAddress}:${sock.remotePort} = ${data}`);

        data_str = String(data).split("");

        // Skip the first 8 bytes. (0xFF)
        var offset = 8;

        // '0x4E' as for AUTHORIZE_HEADER
        if (data_str[offset] != 0x4E && socket_manager.IsSocketAuthorized(sock))
        {
            socket_manager.Send(sock, data);
            return;
        }

        offset++;

        var valid = ValidateAuthorization(data_str, offset);
        if (valid)
        {
            socket_manager.AddSocket(sock);
        }
    });

    sock.on('error', (err) => {
        console.log('Caught flash policy server socket error: ');
        console.log(err.stack);
    });

    sock.on('close', (data) => {
        socket_manager.EraseSocket(sock);
        console.log(`connection closed: ${sock.remoteAddress}:${sock.remotePort}`);
    });

}).listen(port, host);

function ValidateAuthorization(data, offset)
{
    var buffer = "";

    while(data[offset] && data[offset] != '\0')
    {
        buffer += data[offset];
        offset++;
    }

    return (buffer == config.key);
}

console.log(`Server listening on ${host}:${port}`);