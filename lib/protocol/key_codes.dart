/// Android `KeyEvent` key codes used by the remote. The protocol's RemoteKeyCode
/// enum mirrors these values exactly.
abstract final class Keys {
  static const home = 3;
  static const back = 4;
  static const num0 = 7; // 0..9 = 7..16
  static const dpadUp = 19;
  static const dpadDown = 20;
  static const dpadLeft = 21;
  static const dpadRight = 22;
  static const dpadCenter = 23;
  static const volumeUp = 24;
  static const volumeDown = 25;
  static const power = 26;
  static const enter = 66;
  static const del = 67;
  static const menu = 82;
  static const search = 84;
  static const mediaPlayPause = 85;
  static const mediaStop = 86;
  static const mediaNext = 87;
  static const mediaPrevious = 88;
  static const mediaRewind = 89;
  static const mediaFastForward = 90;
  static const volumeMute = 164; // not KEYCODE_MUTE (91), which mutes the microphone
  static const info = 165;
  static const channelUp = 166;
  static const channelDown = 167;
  static const tv = 170;
  static const guide = 172;
  static const captions = 175;
  static const settings = 176;
  static const tvInput = 178;
  static const progRed = 183;
  static const progGreen = 184;
  static const progYellow = 185;
  static const progBlue = 186;
  static const assist = 219;

  static int digit(int n) {
    assert(n >= 0 && n <= 9);
    return num0 + n;
  }
}
