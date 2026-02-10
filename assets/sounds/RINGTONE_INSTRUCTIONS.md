# Ringtone Configuration

## Current Setup: System Default Ringtone ✅

The app is configured to use the **system's default ringtone** - no additional audio files needed!

### How It Works:
- Uses Android's built-in `RingtoneManager.TYPE_RINGTONE`
- Plays the default ringtone set in your phone's settings
- Works out of the box, no setup required
- Automatically stops when call is accepted or rejected

### Benefits:
✅ No audio files to download or manage  
✅ Uses familiar phone ringtone  
✅ Respects user's volume settings  
✅ Works immediately after install  

### Alternative: Custom Ringtone (Optional)

If you want to use a custom sound instead:

1. Download a ringtone MP3 file
2. Place it in: `assets/sounds/ringtone.mp3`
3. Update the code in `signaling_service.dart`:
   ```dart
   // Change from:
   await _ringtonePlayer.play(AssetSource('sounds/ringtone.mp3'));
   
   // To use system default (current):
   // Uses RingtoneManager - no file needed!
   ```

### Testing:
- Make a call from web client
- Mobile should play default ringtone
- If no sound, check phone volume settings

