
const options = program.opts();
const SERVER_KEY = options.key;
if (!SERVER_KEY) {
  console.error('ERROR: FCM server key not provided. Set FCM_SERVER_KEY in .env or pass via -k.');
  process.exit(1);
}

const payload = {
  to: options.token,
  priority: 'high',
  data: {
    type: 'incoming_call',
    callId: options.id,
    callerName: options.caller,
    callerId: '+1000000000',
    isVideo: 'false'
  }
};

(async () => {
  try {
    const res = await axios.post('https://fcm.googleapis.com/fcm/send', payload, {
      headers: {
        Authorization: `key=${SERVER_KEY}`,
        'Content-Type': 'application/json'
      }
    });
    console.log('FCM response status:', res.status);
    console.log('Response data:', res.data);
  } catch (err) {
    console.error('FCM send error:', err.response ? err.response.data : err.message);
    process.exit(1);
  }
})();
