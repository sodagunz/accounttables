export const firebaseConfig = {
  apiKey: "AIzaSyAb0w_8S_pAUvwC-jMI3LqNMR9SL-HPRAE",
  authDomain: "contabilizar-78c2d.firebaseapp.com",
  projectId: "contabilizar-78c2d",
  storageBucket: "contabilizar-78c2d.firebasestorage.app",
  messagingSenderId: "925458846223",
  appId: "1:925458846223:web:c18a094732b3d27e7ec97a",
  measurementId: "G-B575X9YBT8",
};

export function hasFirebaseConfig(config) {
  return Boolean(
    config.apiKey &&
      config.authDomain &&
      config.projectId &&
      config.appId,
  );
}
