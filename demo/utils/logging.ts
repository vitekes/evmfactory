export const log = {
  info(message: string) {
    console.log(`[INFO] ${message}`);
  },
  success(message: string) {
    console.log(`[OK] ${message}`);
  },
  warn(message: string) {
    console.warn(`[WARN] ${message}`);
  },
  error(message: string) {
    console.error(`[ERROR] ${message}`);
  },
};
