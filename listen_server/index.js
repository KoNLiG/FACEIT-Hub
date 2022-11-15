var net = require('net');
const config = require("./config.json");

class SocketManager
{
    sockets;

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
        const idx = this.sockets.indexOf(socket);
        if (idx != -1)
        {
            this.sockets.splice(idx, 1);
        }
    }

    Send(sender, data)
    {
        this.sockets.forEach(socket => {
            if(socket != sender)
                socket.write(data);
        });
    }

    IsSocketAuthorized(socket)
    {
        return (this.sockets.indexOf(socket) != -1);
    }
}

const socketManager = new SocketManager({});

const hostname = '0.0.0.0';

net.createServer(sock => {
    console.log(`connected: ${sock.remoteAddress}:${sock.remotePort}`);

    sock.on('data', (data) => {
        let packetLength = 0, sequenceNumber = 0;

        // Handle combined or fragmented reads, meaning that we read segment by segment
        // according to Nagle's algorithm.
        // 'data.length > packetLength' meaning that there's more packet segments.
        do
        {
            // Read a 16bit packet using little endian (LE).
            packetLength = data.readInt16LE(sequenceNumber);

            // startIdx '+ 4' to explicitly skip the first 4 bytes which indicates the packet length.
            ReadPacketSegment(data.toString('utf-8', sequenceNumber + 4, sequenceNumber + packetLength), sock);
        } while (data.length > (sequenceNumber += packetLength));
    });

    sock.on('error', (err) => {
        socketManager.EraseSocket(sock);
        console.error(err.stack);
    });

    sock.on('close', (data) => {
        socketManager.EraseSocket(sock);
        console.log(`connection closed: ${sock.remoteAddress}:${sock.remotePort}`);
    });
}).listen(config.port, hostname);

const ReadPacketSegment = (data, socket) => {
    console.log(`${socket.remoteAddress}:${socket.remotePort} > (${data})`);

    let [header, key] = split(data, 1);

    // '0x4E' as for AUTHORIZE_HEADER
    if (header != 0x4E && socketManager.IsSocketAuthorized(socket))
    {
        socketManager.Send(socket, data);
        return;
    }

    key = key.replace('\0', '');
    if (key == config.key)
    {
        socketManager.AddSocket(socket);
    }
}

const split = (str, index) => [str.slice(0, index), str.slice(index)];

console.log(`Server listening on ${hostname}:${config.port}`);