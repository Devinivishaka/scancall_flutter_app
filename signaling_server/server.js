const WebSocket = require('ws');

const PORT = 8080;
const wss = new WebSocket.Server({ port: PORT });

// Store connected clients by room
const rooms = new Map();

wss.on('connection', (ws) => {
  console.log('New client connected');

  let currentRoom = null;
  let clientId = generateId();

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      console.log('Received:', data.type, 'from client:', clientId);

      switch (data.type) {
        case 'join':
          currentRoom = data.room;

          // Add client to room
          if (!rooms.has(currentRoom)) {
            rooms.set(currentRoom, new Set());
          }
          rooms.get(currentRoom).add(ws);

          // Send confirmation
          ws.send(JSON.stringify({
            type: 'joined',
            room: currentRoom,
            clientId: clientId
          }));

          console.log(`Client ${clientId} joined room: ${currentRoom}`);
          break;

        case 'offer':
          // Forward offer to other clients in the room
          broadcastToRoom(currentRoom, ws, {
            type: 'offer',
            sdp: data.sdp,
            from: clientId
          });
          console.log(`Offer forwarded from ${clientId}`);
          break;

        case 'answer':
          // Forward answer to other clients in the room
          broadcastToRoom(currentRoom, ws, {
            type: 'answer',
            sdp: data.sdp,
            from: clientId
          });
          console.log(`Answer forwarded from ${clientId}`);
          break;

        case 'call-accepted':
          // Notify other side that call was accepted
          broadcastToRoom(currentRoom, ws, {
            type: 'call-accepted',
            from: clientId
          });
          console.log(`Call accepted by ${clientId}, notifying others`);
          break;

        case 'call-ended':
          // Notify other side that call was ended
          broadcastToRoom(currentRoom, ws, {
            type: 'call-ended',
            from: clientId
          });
          console.log(`Call ended by ${clientId}, notifying others`);
          break;

        case 'reject':
          // Notify other side that call was rejected
          broadcastToRoom(currentRoom, ws, {
            type: 'call-rejected',
            from: clientId
          });
          console.log(`Call rejected by ${clientId}, notifying others`);
          break;

        case 'ice-candidate':
          // Forward ICE candidate to other clients in the room
          broadcastToRoom(currentRoom, ws, {
            type: 'ice-candidate',
            candidate: data.candidate,
            from: clientId
          });
          console.log(`ICE candidate forwarded from ${clientId}`);
          break;

        case 'leave':
          leaveRoom(ws, currentRoom);
          console.log(`Client ${clientId} left room: ${currentRoom}`);
          break;

        default:
          console.log('Unknown message type:', data.type);
      }
    } catch (error) {
      console.error('Error handling message:', error);
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Invalid message format'
      }));
    }
  });

  ws.on('close', () => {
    console.log(`Client ${clientId} disconnected`);
    if (currentRoom) {
      leaveRoom(ws, currentRoom);
    }
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });
});

function broadcastToRoom(room, sender, message) {
  if (!rooms.has(room)) return;

  const clients = rooms.get(room);
  clients.forEach((client) => {
    if (client !== sender && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(message));
    }
  });
}

function leaveRoom(ws, room) {
  if (rooms.has(room)) {
    rooms.get(room).delete(ws);

    // Clean up empty rooms
    if (rooms.get(room).size === 0) {
      rooms.delete(room);
    }
  }
}

function generateId() {
  return Math.random().toString(36).substring(2, 15);
}

console.log(`WebSocket signaling server running on port ${PORT}`);
console.log('Waiting for connections...');
