// `RussianShelf --selftest`, for the Mac Pro: everything the app relies on,
// checked on the Mac it runs on, one line each. Nothing is changed.
//
//   - the AES and signature code with 10.9's own CommonCrypto and Security
//     (a shelf sealed with the real key, as shipped, opens; altered, it doesn't)
//   - subtitles of both kinds
//   - the bundled Python (with OpenSSL), QuickJS, ffmpeg and yt-dlp start
//   - certificates: YouTube's is accepted, bad ones are refused (needs the
//     network; skipped offline)
//   - the study folder, git, and the shelf in it
//   - a downloaded video, if there is one, is something AVFoundation can play

int RSSelfTestRun(void);
