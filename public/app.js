import { initializeApp } from "https://www.gstatic.com/firebasejs/12.14.0/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/12.14.0/firebase-auth.js";
import {
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "https://www.gstatic.com/firebasejs/12.14.0/firebase-firestore.js";
import { firebaseConfig, hasFirebaseConfig } from "./firebase-config.js";

const LEDGER_CACHE_SCHEMA_VERSION = 3;
const LOCAL_LEDGER_SCHEMA_VERSION = 1;
const EXCHANGE_RATE_CACHE_SCHEMA_VERSION = 1;
const LAST_SESSION_KEY = "contabilizar:lastSession";
const LOCAL_LEDGER_ID = "local";
const LOCAL_LEDGER_KEY = "contabilizar:localLedger";
const DEFAULT_LOCAL_LEDGER_NAME = "Libro contable de desconocido";
const TUTORIAL_STATE_KEY = "contabilizar:tutorialState";
const FILTER_WINDOW_KEY = "contabilizar:filterWindow";
const COLOR_SCHEME_KEY = "contabilizar:colorScheme";

const initialColorScheme = loadColorScheme();
applyColorScheme(initialColorScheme);

const app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    ledger: loadStartupLedgerCache(),
    tutorialState: loadTutorialState(),
    filterWindow: loadFilterWindow(),
    colorScheme: initialColorScheme,
  },
});

setupFirebaseAuth(app);
setupLastAccountStorage(app);
setupTutorialDriver(app);

app.ports.focusAccountTool.subscribe(() => {
  focusAccountTool();
});

app.ports.openDisclosure.subscribe((id) => {
  const el = document.getElementById(id);
  if (el) el.open = true;
  window.requestAnimationFrame(() => {
    window.accounttablesTutorialDriver?.refresh();
  });
});

app.ports.focusElement.subscribe((selector) => {
  const el = document.querySelector(selector);
  if (el) el.focus();
});

app.ports.saveTutorialState.subscribe((state) => {
  saveTutorialState(state);
});

app.ports.saveFilterWindowSelection.subscribe((filterWindow) => {
  saveFilterWindow(filterWindow);
});

app.ports.saveColorSchemeSelection.subscribe((colorScheme) => {
  saveColorScheme(colorScheme);
  applyColorScheme(colorScheme);
});

app.ports.generateExpenseId.subscribe(() => {
  app.ports.expenseIdGenerated.send(uuidv7());
});

app.ports.exportTable.subscribe((payload) => {
  if (payload.format === "xlsx" && window.XLSX) {
    downloadXlsx(payload);
  } else {
    downloadCsv({
      ...payload,
      filename: payload.filename.replace(/\.xlsx$/i, ".csv"),
    });
  }
});

function downloadCsv(payload) {
  const lines = [payload.headers, ...payload.rows.map((row) => row.cells)];
  const csv = lines.map((row) => row.map(escapeCsv).join(",")).join("\r\n");
  downloadBlob(payload.filename, "text/csv;charset=utf-8", "\uFEFF" + csv);
}

function downloadXlsx(payload) {
  const rows = [payload.headers, ...payload.rows.map((row) => row.cells)];
  const worksheet = XLSX.utils.aoa_to_sheet(rows);
  const range = XLSX.utils.decode_range(worksheet["!ref"]);

  worksheet["!cols"] = [
    { wch: 18 },
    { wch: 14 },
    { wch: 28 },
    { wch: 16 },
    { wch: 16 },
    { wch: 18 },
    { wch: 4 },
    { wch: 18 },
  ];

  worksheet["!freeze"] = { xSplit: 0, ySplit: 1 };
  worksheet["!autofilter"] = { ref: worksheet["!ref"] };

  for (let column = range.s.c; column <= range.e.c; column += 1) {
    const cell = worksheet[XLSX.utils.encode_cell({ r: 0, c: column })];
    if (cell) {
      cell.s = { font: { bold: true }, fill: { fgColor: { rgb: "EEF5F2" } } };
    }
  }

  payload.rows.forEach((row, index) => {
    if (row.type === "subtotal" || row.type === "total") {
      for (let column = range.s.c; column <= range.e.c; column += 1) {
        const cell = worksheet[XLSX.utils.encode_cell({ r: index + 1, c: column })];
        if (cell) {
          cell.s = {
            font: { bold: true },
            fill: {
              fgColor: {
                rgb: row.type === "total" ? "E7F2EE" : "F8FAF9",
              },
            },
          };
        }
      }
    }
  });

  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, payload.sheetName || "Gastos");
  XLSX.writeFile(workbook, payload.filename);
}

function escapeCsv(value) {
  const text = String(value ?? "");
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }

  return text;
}

function downloadBlob(filename, mimeType, content) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function setupFirebaseAuth(app) {
  if (!hasFirebaseConfig(firebaseConfig)) {
    setupExchangeRateLookup(app, null, null);
    app.ports.authStateChanged.send({ status: "unconfigured" });
    return;
  }

  const firebaseApp = initializeApp(firebaseConfig);
  const auth = getAuth(firebaseApp);
  const db = getFirestore(firebaseApp);
  const provider = new GoogleAuthProvider();

  setupFirestore(app, auth, db);
  setupExchangeRateLookup(app, auth, db);

  onAuthStateChanged(auth, async (user) => {
    if (user) {
      try {
        await ensureUserEmailIndex(auth, db);
        const acceptedInviteLedgerIds = await acceptPendingInvites(auth, db);
        app.ports.authStateChanged.send({
          status: "signed-in",
          user: serializeUser(user, acceptedInviteLedgerIds[0] || null),
        });
      } catch (error) {
        console.error("Firebase invite acceptance failed", error);
        app.ports.authStateChanged.send({
          status: "error",
          message: firestoreErrorMessage(error),
        });
      }
    } else {
      clearLastSession();
      app.ports.authStateChanged.send({ status: "signed-out" });
    }
  });

  app.ports.signInWithGoogle.subscribe(() => {
    signInWithPopup(auth, provider).catch((error) => {
      console.error("Firebase Google sign-in failed", error);
      app.ports.authStateChanged.send({
        status: "error",
        message: firebaseAuthErrorMessage(error),
      });
    });
  });

  app.ports.signOutUser.subscribe(() => {
    clearLastSession();
    signOut(auth).catch((error) => {
      console.error("Firebase sign-out failed", error);
      app.ports.authStateChanged.send({
        status: "error",
        message: firebaseAuthErrorMessage(error),
      });
    });
  });
}

function setupLastAccountStorage(app) {
  app.ports.saveLastAccountSelection.subscribe(({ ledgerId, accountId }) => {
    saveLastAccountId(ledgerId, accountId);
  });
}

function setupTutorialDriver(app) {
  const driverFactory = window.driver?.js?.driver;

  if (!driverFactory) {
    console.warn("Driver.js is not available; tutorial tour disabled.");
    return;
  }

  let driverObj = null;
  const baseDriverConfig = {
    animate: true,
    smoothScroll: true,
    allowClose: false,
    overlayClickBehavior: () => {},
    overlayOpacity: 0.585,
    stagePadding: 6,
    stageRadius: 6,
    popoverClass: "driverjs-theme-accounttables",
    nextBtnText: "Siguiente",
    prevBtnText: "Atras",
    doneBtnText: "Finalizar",
  };

  const emitTutorialAction = (action, payload = {}) => {
    const port = app.ports.tutorialAction;
    if (port?.send) {
      port.send({ action, ...payload });
    }
  };

  const destroyTutorial = () => {
    if (driverObj) {
      driverObj.destroy();
      driverObj = null;
    }
  };

  const ensureDriver = () => {
    if (driverObj) {
      return driverObj;
    }

    driverObj = driverFactory(baseDriverConfig);

    return driverObj;
  };

  const popoverButtonsFor = (step) => {
    const buttons = [];

    if (step?.showBack) {
      buttons.push("previous");
    }

    if (step?.showNext || step?.done) {
      buttons.push("next");
    }

    if (step?.showSkip) {
      buttons.push("close");
    }

    return buttons;
  };

  const labelCloseButton = (popover) => {
    const closeButton =
      popover?.closeButton ||
      popover?.closeBtn ||
      document.querySelector(".driver-popover-close-btn");

    if (!closeButton) return;

    closeButton.textContent = "Saltar este paso";
    closeButton.setAttribute("aria-label", "Saltar este paso");
    closeButton.setAttribute("title", "Saltar este paso");
  };

  const openTutorialDisclosures = (ids) => {
    if (!Array.isArray(ids)) return;

    ids.forEach((id) => {
      const el = document.getElementById(String(id || ""));
      if (el) el.open = true;
    });
  };

  const showTutorialStep = (step, retry = true) => {
    openTutorialDisclosures(step?.openDisclosures);

    const selector = String(step?.selector || "");
    const target = selector ? document.querySelector(selector) : null;
    const isMobile = window.matchMedia("(max-width: 520px)").matches;

    if (selector && !target) {
      if (retry) {
        window.requestAnimationFrame(() => showTutorialStep(step, false));
        return;
      }

      destroyTutorial();
      emitTutorialAction("target-missing", {
        selector,
        step: String(step?.step || ""),
      });
      return;
    }

    const driver = ensureDriver();
    const showButtons = popoverButtonsFor(step);

    target?.scrollIntoView({
      behavior: isMobile ? "auto" : "smooth",
      block: isMobile ? "center" : "nearest",
      inline: "nearest",
    });

    const highlightStep = () => {
      driver.setConfig({
        ...baseDriverConfig,
        nextBtnText: step?.done ? "Finalizar" : "Siguiente",
        stagePadding: isMobile ? 4 : baseDriverConfig.stagePadding,
        popoverOffset: isMobile ? 8 : 10,
      });

      driver.highlight({
        element: selector || undefined,
        disableActiveInteraction: !step?.allowTargetClick,
        popover: {
          title: String(step?.title || ""),
          description: String(step?.description || ""),
          side: step?.side || "bottom",
          align: step?.align || "start",
          showButtons,
          nextBtnText: step?.done ? "Finalizar" : "Siguiente",
          prevBtnText: "Atras",
          doneBtnText: "Finalizar",
          onPopoverRender: labelCloseButton,
          onNextClick: () => emitTutorialAction(step?.done ? "done" : "next"),
          onPrevClick: () => emitTutorialAction("back"),
          onCloseClick: () => emitTutorialAction("skip"),
        },
      });
    };

    if (isMobile && target) {
      window.requestAnimationFrame(highlightStep);
    } else {
      highlightStep();
    }
  };

  const refreshTutorial = () => {
    if (driverObj?.isActive()) {
      driverObj.refresh();
    }
  };

  if (app.ports.showTutorialStep?.subscribe) {
    app.ports.showTutorialStep.subscribe(showTutorialStep);
  }

  if (app.ports.hideTutorial?.subscribe) {
    app.ports.hideTutorial.subscribe(destroyTutorial);
  }

  if (app.ports.refreshTutorial?.subscribe) {
    app.ports.refreshTutorial.subscribe(refreshTutorial);
  }

  window.accounttablesTutorialDriver = {
    showStep: showTutorialStep,
    hide: destroyTutorial,
    refresh: refreshTutorial,
  };
}

function focusAccountTool() {
  const adminTool = document.getElementById("admin-tool");
  const accountsTool = document.getElementById("accounts-tool");
  const accountInput = document.getElementById("new-account-name");

  if (adminTool) {
    adminTool.open = true;
  }

  if (accountsTool) {
    accountsTool.open = true;
    accountsTool.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  window.requestAnimationFrame(() => {
    accountInput?.focus();
  });
}

function setupExchangeRateLookup(app, auth, db) {
  app.ports.loadExchangeRate.subscribe(async ({ ledgerId, date, casa }) => {
    const normalizedDate = String(date || "").trim();
    const normalizedCasa = String(casa || "bolsa").trim() || "bolsa";
    const effectiveLedgerId = String(ledgerId || LOCAL_LEDGER_ID).trim() || LOCAL_LEDGER_ID;

    if (!normalizedDate) {
      app.ports.exchangeRateLoaded.send({
        status: "error",
        date: normalizedDate,
        source: "stored",
        message: "Falta la fecha para buscar la cotización bolsa.",
      });
      return;
    }

    try {
      const localEntry = loadExchangeRateCache(
        auth?.currentUser?.uid,
        effectiveLedgerId,
        normalizedCasa,
        normalizedDate,
      );
      if (localEntry) {
        app.ports.exchangeRateLoaded.send({
          status: "loaded",
          date: normalizedDate,
          sale: localEntry.sale,
          source: "local-cache",
        });
        return;
      }

      const canUseFirestore =
        Boolean(db) && Boolean(auth?.currentUser?.uid) && effectiveLedgerId !== LOCAL_LEDGER_ID;

      if (canUseFirestore) {
        try {
          const rateRef = doc(
            db,
            "ledgers",
            effectiveLedgerId,
            "exchangeRates",
            exchangeRateDocumentId(normalizedCasa, normalizedDate),
          );
          const rateSnapshot = await getDoc(rateRef);
          if (rateSnapshot.exists()) {
            const storedRate = Number(rateSnapshot.data()?.sale);
            if (Number.isFinite(storedRate) && storedRate > 0) {
              cacheExchangeRate(
                auth.currentUser.uid,
                effectiveLedgerId,
                normalizedCasa,
                normalizedDate,
                storedRate,
              );
              app.ports.exchangeRateLoaded.send({
                status: "loaded",
                date: normalizedDate,
                sale: storedRate,
                source: "firestore",
              });
              return;
            }
          }
        } catch (error) {
          console.warn("Could not read exchange rate from Firestore", error);
        }
      }

      const fetchedRate = isToday(normalizedDate)
        ? await fetchLiveExchangeRateFromApi(normalizedCasa)
        : await fetchHistoricalExchangeRateFromApi(normalizedCasa, normalizedDate);

      cacheExchangeRate(
        auth?.currentUser?.uid,
        effectiveLedgerId,
        normalizedCasa,
        normalizedDate,
        fetchedRate,
      );

      if (canUseFirestore) {
        await setDoc(
          doc(
            db,
            "ledgers",
            effectiveLedgerId,
            "exchangeRates",
            exchangeRateDocumentId(normalizedCasa, normalizedDate),
          ),
          {
            id: exchangeRateDocumentId(normalizedCasa, normalizedDate),
            casa: normalizedCasa,
            date: normalizedDate,
            sale: fetchedRate,
            updatedAt: serverTimestamp(),
            fetchedAt: new Date().toISOString(),
          },
          { merge: true },
        ).catch((error) => {
          console.warn("Could not persist exchange rate to Firestore", error);
        });
      }

      app.ports.exchangeRateLoaded.send({
        status: "loaded",
        date: normalizedDate,
        sale: fetchedRate,
        source: isToday(normalizedDate) ? "api-live" : "api",
      });
    } catch (error) {
      console.error("Exchange rate load failed", error);
      app.ports.exchangeRateLoaded.send({
        status: "error",
        date: normalizedDate,
        source: "api",
        message: exchangeRateErrorMessage(error, normalizedDate),
      });
    }
  });
}

function setupFirestore(app, auth, db) {
  app.ports.loadLedgerData.subscribe(async ({ ledgerId }) => {
    try {
      if (ledgerId === LOCAL_LEDGER_ID || !auth.currentUser?.uid) {
        emitLocalLedger(app, getLocalLedgerPayload());
        return;
      }

      emitCachedLedger(app, auth, ledgerId);
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Firestore ledger load failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.appendEvent.subscribe(async (payload) => {
    const ledgerId = payload.ledgerId;
    const event = payload.event;
    if (!ledgerId) {
      console.error("No ledgerId provided for appendEvent");
      return;
    }
    if (!event) {
      console.error("No event provided for appendEvent");
      return;
    }

    if (ledgerId === LOCAL_LEDGER_ID || !auth.currentUser?.uid) {
      const localLedger = getLocalLedgerPayload();
      const actualSeq = (localLedger.lastEventSequence || 0) + 1;
      const localEvent = { ...event, sequence: actualSeq };
      emitLocalLedger(
        app,
        cacheLocalLedgerPayload({
          ...localLedger,
          events: [...localLedger.events, localEvent],
          lastEventSequence: actualSeq,
        }),
      );
      return;
    }

    const eventId = uuidv7();
    const uid = auth.currentUser?.uid;
    const cachedPayload = uid && loadLedgerCache(uid, ledgerId);
    const estimatedSeq = (cachedPayload?.lastEventSequence || 0) + 1;
    const newEvent = { ...event, sequence: estimatedSeq, id: eventId };

    // Update cache immediately (sync, no network)
    if (cachedPayload) {
      cacheLedgerPayload(uid, {
        ...cachedPayload,
        events: [...cachedPayload.events, newEvent],
      });
    }

    // Firestore transaction (slow — don't block cache on this)
    try {
      const ledgerRef = doc(db, "ledgers", ledgerId);
      const eventRef = doc(db, "ledgers", ledgerId, "events", eventId);

      await runTransaction(db, async (transaction) => {
        const ledgerSnapshot = await transaction.get(ledgerRef);
        if (!ledgerSnapshot.exists()) {
          throw new Error("Ledger does not exist");
        }

        const actualSeq = (ledgerSnapshot.data().nextEventSequence || 0) + 1;

        transaction.set(
          eventRef,
          {
            ...event,
            sequence: actualSeq,
            id: eventId,
            createdAt: serverTimestamp(),
          },
          { merge: true },
        );

        transaction.update(ledgerRef, {
          nextEventSequence: actualSeq,
          updatedAt: serverTimestamp(),
        });
      });
    } catch (error) {
      console.error("Firestore event append failed", error);
    }
  });

  app.ports.saveAccount.subscribe(async ({ ledgerId, name }) => {
    try {
      if (ledgerId === LOCAL_LEDGER_ID || !auth.currentUser?.uid) {
        const trimmedName = String(name || "").trim();
        if (!trimmedName) {
          throw new Error("El nombre de la cuenta no puede estar vacío.");
        }

        const localLedger = getLocalLedgerPayload();
        const account = {
          id: uuidv7(),
          name: trimmedName,
          deletedAt: null,
        };
        emitLocalLedger(
          app,
          cacheLocalLedgerPayload({
            ...localLedger,
            accounts: [account, ...localLedger.accounts],
          }),
        );
        return;
      }

      await ensureLedger(auth, db, ledgerId);
      const trimmedName = String(name || "").trim();

      if (!trimmedName) {
        throw new Error("El nombre de la cuenta no puede estar vacío.");
      }

      const accountId = uuidv7();
      const account = {
        id: accountId,
        name: trimmedName,
        createdAt: new Date().toISOString(),
      };
      const cachedLedger = upsertCachedAccount(auth.currentUser?.uid, ledgerId, account);
      emitLedgerPayload(app, cachedLedger);
      await setDoc(
        doc(db, "ledgers", ledgerId, "accounts", accountId),
        {
          ...account,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Firestore account save failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.deleteAccount.subscribe(async ({ ledgerId, accountId }) => {
    try {
      if (ledgerId === LOCAL_LEDGER_ID || !auth.currentUser?.uid) {
        const localLedger = getLocalLedgerPayload();
        const deletedAt = new Date().toISOString();
        emitLocalLedger(
          app,
          cacheLocalLedgerPayload({
            ...localLedger,
            accounts: localLedger.accounts.map((account) =>
              account.id === accountId ? { ...account, deletedAt } : account,
            ),
          }),
        );
        return;
      }

      await ensureLedger(auth, db, ledgerId);
      const deletedAt = new Date().toISOString();
      const cachedLedger = softDeleteCachedAccount(
        auth.currentUser?.uid,
        ledgerId,
        accountId,
        deletedAt,
      );
      emitLedgerPayload(app, cachedLedger);
      let batch = writeBatch(db);
      let writeCount = 0;

      async function setInBatch(ref, data) {
        batch.set(ref, data, { merge: true });
        writeCount += 1;

        if (writeCount >= 450) {
          await batch.commit();
          batch = writeBatch(db);
          writeCount = 0;
        }
      }

      await setInBatch(doc(db, "ledgers", ledgerId, "accounts", accountId), {
        deletedAt,
        updatedAt: serverTimestamp(),
      });

      const expenseSnapshot = await getDocs(collection(db, "ledgers", ledgerId, "expenses"));
      for (const documentSnapshot of expenseSnapshot.docs) {
        const expense = documentSnapshot.data();
        if (expense.accountId === accountId && !expense.deletedAt) {
          await setInBatch(documentSnapshot.ref, {
            deletedAt,
            updatedAt: serverTimestamp(),
          });
        }
      }

      if (writeCount > 0) {
        await batch.commit();
      }
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Firestore account delete failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.inviteLedgerGuest.subscribe(async ({ ledgerId, email }) => {
    try {
      await ensureLedger(auth, db, ledgerId);
      const normalizedEmail = normalizeEmail(email);
      if (!normalizedEmail) {
        throw new Error("El email no puede estar vacío.");
      }

      const ledgerSnapshot = await getDoc(doc(db, "ledgers", ledgerId));
      const ledger = ledgerSnapshot.data();
      if (ledger?.ownerUid !== auth.currentUser?.uid) {
        throw new Error("Solo el owner puede invitar usuarios.");
      }

      const existingUser = await loadUserByEmail(db, normalizedEmail);
      if (existingUser?.uid) {
        if (existingUser.uid === ledger.ownerUid) {
          throw new Error("Ese email ya pertenece al owner.");
        }

        await grantLedgerAccess(db, ledgerId, {
          uid: existingUser.uid,
          email: normalizedEmail,
          displayName: existingUser.displayName || normalizedEmail,
        });
        await deleteDoc(doc(db, "emailInvites", normalizedEmail, "ledgers", ledgerId)).catch(
          (error) => {
            if (error?.code !== "not-found") {
              throw error;
            }
          },
        );
      } else {
        await setDoc(
          doc(db, "emailInvites", normalizedEmail, "ledgers", ledgerId),
          {
            ledgerId,
            ledgerName: ledger?.name || "Libro contable",
            ownerUid: auth.currentUser.uid,
            ownerEmail: normalizeEmail(auth.currentUser.email),
            invitedEmail: normalizedEmail,
            createdAt: new Date().toISOString(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        await updateDoc(doc(db, "ledgers", ledgerId), {
          invitedEmails: arrayUnion(normalizedEmail),
          updatedAt: serverTimestamp(),
        });
      }
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Firestore guest invite failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.removeLedgerGuest.subscribe(async ({ ledgerId, uid }) => {
    try {
      await ensureLedger(auth, db, ledgerId);
      const ledgerRef = doc(db, "ledgers", ledgerId);
      const ledgerSnapshot = await getDoc(ledgerRef);
      const ledger = ledgerSnapshot.data();

      if (ledger?.ownerUid !== auth.currentUser?.uid) {
        throw new Error("Solo el owner puede quitar invitados.");
      }

      const member = (ledger.members || []).find((candidate) => candidate.uid === uid);
      if (!member || uid === ledger.ownerUid) {
        throw new Error("No se puede quitar este miembro.");
      }

      await updateDoc(ledgerRef, {
        memberUids: arrayRemove(uid),
        memberEmails: arrayRemove(normalizeEmail(member.email)),
        members: arrayRemove(member),
        updatedAt: serverTimestamp(),
      });
      await deleteDoc(doc(db, "userLedgers", uid, "ledgers", ledgerId));
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Firestore guest removal failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.updateLedgerName.subscribe(async ({ ledgerId, name }) => {
    try {
      if (ledgerId === LOCAL_LEDGER_ID || !auth.currentUser?.uid) {
        const trimmedName = String(name || "").trim();
        if (!trimmedName) {
          throw new Error("El nombre del libro contable no puede estar vacío.");
        }

        const localLedger = getLocalLedgerPayload();
        emitLocalLedger(
          app,
          cacheLocalLedgerPayload({
            ...localLedger,
            ledgers: [
              {
                id: LOCAL_LEDGER_ID,
                name: trimmedName,
                ownerUid: "",
                members: [],
                invitedEmails: [],
              },
            ],
          }),
        );
        return;
      }

      await ensureLedger(auth, db, ledgerId);
      const trimmedName = String(name || "").trim();
      if (!trimmedName) {
        throw new Error("El nombre del libro contable no puede estar vacío.");
      }

      const ledgerRef = doc(db, "ledgers", ledgerId);
      const ledgerSnapshot = await getDoc(ledgerRef);
      const ledger = ledgerSnapshot.data();
      if (ledger?.ownerUid !== auth.currentUser?.uid) {
        throw new Error("Solo el owner puede renombrar el libro contable.");
      }

      await updateDoc(ledgerRef, {
        name: trimmedName,
        updatedAt: serverTimestamp(),
      });
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Firestore ledger rename failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.prepareLocalMigration.subscribe(async () => {
    try {
      await ensureUserEmailIndex(auth, db);
      await ensurePersonalLedger(auth, db);
      await acceptPendingInvites(auth, db);

      const ledgers = await loadLedgerSummaries(auth, db);
      const selectedLedgerId =
        ledgers.find((ledger) => ledger.id === auth.currentUser?.uid)?.id || ledgers[0]?.id || "";

      app.ports.localMigrationPrepared.send({
        status: "ready",
        ledgers,
        selectedLedgerId,
      });
    } catch (error) {
      console.error("Local migration preparation failed", error);
      app.ports.localMigrationPrepared.send({
        status: "error",
        message: firestoreErrorMessage(error),
      });
    }
  });

  app.ports.mergeLocalLedgerToFirestore.subscribe(async ({ ledgerId }) => {
    try {
      await ensureUserEmailIndex(auth, db);
      await ensurePersonalLedger(auth, db);
      await acceptPendingInvites(auth, db);
      await mergeLocalLedgerIntoFirestore(auth, db, ledgerId);
      clearLocalLedgerCache();
      await loadLedger(app, auth, db, ledgerId);
    } catch (error) {
      console.error("Local migration upload failed", error);
      app.ports.ledgerLoaded.send({
        status: "error",
        ledgerId,
        message: firestoreErrorMessage(error),
      });
    }
  });
}

async function loadLedger(app, auth, db, ledgerId) {
  await ensureUserEmailIndex(auth, db);
  await ensurePersonalLedger(auth, db);
  await acceptPendingInvites(auth, db);

  const ledgers = await loadLedgerSummaries(auth, db);
  const selectedLedgerId = ledgers.some((ledger) => ledger.id === ledgerId)
    ? ledgerId
    : ledgers[0]?.id || auth.currentUser?.uid || "";

  const cachedPayload = loadLedgerCache(auth.currentUser?.uid, selectedLedgerId);
  const lastEventSequence = cachedPayload?.lastEventSequence || 0;

  const [accountSnapshot, eventSnapshot] = await Promise.all([
    getDocs(collection(db, "ledgers", selectedLedgerId, "accounts")),
    getDocs(query(collection(db, "ledgers", selectedLedgerId, "events"), orderBy("sequence"))),
  ]);
  const accounts = accountSnapshot.docs.map((documentSnapshot) =>
    serializeFirestoreDocument(documentSnapshot),
  );
  const remoteEvents = eventSnapshot.docs.map((documentSnapshot) =>
    serializeFirestoreDocument(documentSnapshot),
  );

  const cachedEvents = cachedPayload?.events || [];
  const cachedIds = new Set(cachedEvents.map((e) => e.id));
  const remoteIds = new Set(remoteEvents.map((e) => e.id));

  // Push cached events missing from Firestore
  const pushBatch = writeBatch(db);
  let pushCount = 0;
  for (const event of cachedEvents) {
    if (event.id && !remoteIds.has(event.id)) {
      pushBatch.set(doc(db, "ledgers", selectedLedgerId, "events", event.id), event, {
        merge: true,
      });
      pushCount += 1;
      if (pushCount >= 450) {
        await pushBatch.commit();
        pushCount = 0;
      }
    }
  }
  if (pushCount > 0) {
    await pushBatch.commit();
  }

  // Merge: start with all cached events, then add remote events not in cache
  const mergedEvents = [...cachedEvents];
  for (const event of remoteEvents) {
    if (event.id && !cachedIds.has(event.id)) {
      mergedEvents.push(event);
    }
  }
  mergedEvents.sort((a, b) => (a.sequence || 0) - (b.sequence || 0));

  const ledgerData = {
    status: "loaded",
    ledgerId: selectedLedgerId,
    lastAccountId: loadLastAccountId(selectedLedgerId),
    ledgers,
    accounts,
    expenses: [],
    events: mergedEvents,
  };

  emitLedgerPayload(app, cacheLedgerPayload(auth.currentUser?.uid, ledgerData));
}

async function ensureLedger(auth, db, ledgerId) {
  if (!auth.currentUser?.uid) {
    throw new Error("No hay una sesión activa.");
  }

  if (ledgerId === auth.currentUser.uid) {
    await ensurePersonalLedger(auth, db);
  }
}

async function mergeLocalLedgerIntoFirestore(auth, db, ledgerId) {
  if (!auth.currentUser?.uid) {
    throw new Error("No hay una sesión activa.");
  }

  if (!ledgerId) {
    throw new Error("Selecciona un libro contable para subir los datos locales.");
  }

  const localLedger = loadLocalLedgerCache();
  if (!localLedger || !hasLocalLedgerData(localLedger)) {
    return;
  }

  const ledgerRef = doc(db, "ledgers", ledgerId);
  const ledgerSnapshot = await getDoc(ledgerRef);
  if (!ledgerSnapshot.exists()) {
    throw new Error("El libro destino no existe.");
  }

  const ledger = ledgerSnapshot.data();
  const localLedgerName = localLedger.ledgers?.[0]?.name || DEFAULT_LOCAL_LEDGER_NAME;
  const shouldRenameTarget =
    ledger.ownerUid === auth.currentUser.uid &&
    localLedgerName &&
    (localLedgerName !== DEFAULT_LOCAL_LEDGER_NAME || isDefaultLedgerName(ledger.name || ""));

  if (shouldRenameTarget) {
    await updateDoc(ledgerRef, {
      name:
        localLedgerName === DEFAULT_LOCAL_LEDGER_NAME
          ? defaultPersonalLedgerName(auth.currentUser)
          : localLedgerName,
      updatedAt: serverTimestamp(),
    });
  }

  const accountBatch = writeBatch(db);
  let accountCount = 0;
  for (const account of localLedger.accounts || []) {
    if (!account?.id) {
      continue;
    }

    accountBatch.set(
      doc(db, "ledgers", ledgerId, "accounts", account.id),
      {
        id: account.id,
        name: account.name || "Cuenta",
        deletedAt: account.deletedAt || null,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    accountCount += 1;
  }

  if (accountCount > 0) {
    await accountBatch.commit();
  }

  const events = [...(localLedger.events || [])].sort(
    (left, right) => (left.sequence || 0) - (right.sequence || 0),
  );
  for (const event of events) {
    await appendEventToFirestore(db, ledgerId, event);
  }
}

async function appendEventToFirestore(db, ledgerId, event) {
  const eventId = uuidv7();
  const ledgerRef = doc(db, "ledgers", ledgerId);
  const eventRef = doc(db, "ledgers", ledgerId, "events", eventId);

  await runTransaction(db, async (transaction) => {
    const ledgerSnapshot = await transaction.get(ledgerRef);
    if (!ledgerSnapshot.exists()) {
      throw new Error("Ledger does not exist");
    }

    const actualSeq = (ledgerSnapshot.data().nextEventSequence || 0) + 1;

    transaction.set(
      eventRef,
      {
        ...event,
        id: eventId,
        sequence: actualSeq,
        createdAt: serverTimestamp(),
      },
      { merge: true },
    );

    transaction.update(ledgerRef, {
      nextEventSequence: actualSeq,
      updatedAt: serverTimestamp(),
    });
  });
}

async function ensurePersonalLedger(auth, db) {
  const uid = auth.currentUser?.uid;

  if (!uid) {
    throw new Error("No hay una sesión activa.");
  }

  const email = normalizeEmail(auth.currentUser.email);
  const member = {
    uid,
    email,
    displayName: auth.currentUser.displayName || email,
  };
  const defaultLedgerName = defaultPersonalLedgerName(auth.currentUser);
  const ledgerRef = doc(db, "ledgers", uid);
  const ledgerSnapshot = await getDoc(ledgerRef);

  if (ledgerSnapshot.exists()) {
    const currentName = ledgerSnapshot.data().name || "";
    await setDoc(
      ledgerRef,
      {
        id: uid,
        name: isDefaultLedgerName(currentName) ? defaultLedgerName : currentName,
        ownerUid: uid,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
  } else {
    await setDoc(ledgerRef, {
      id: uid,
      name: defaultLedgerName,
      ownerUid: uid,
      memberUids: [uid],
      memberEmails: [email],
      members: [member],
      updatedAt: serverTimestamp(),
    });
  }
  await setDoc(
    doc(db, "userLedgers", uid, "ledgers", uid),
    {
      ledgerId: uid,
      role: "owner",
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

async function acceptPendingInvites(auth, db) {
  const uid = auth.currentUser?.uid;
  const email = normalizeEmail(auth.currentUser?.email);
  if (!uid || !email) {
    return [];
  }

  const inviteSnapshot = await getDocs(collection(db, "emailInvites", email, "ledgers"));
  const acceptedLedgerIds = [];
  for (const inviteDocument of inviteSnapshot.docs) {
    const invite = inviteDocument.data();
    const ledgerId = invite.ledgerId || inviteDocument.id;
    const member = {
      uid,
      email,
      displayName: auth.currentUser.displayName || email,
    };

    await grantLedgerAccess(db, ledgerId, member);
    await deleteDoc(inviteDocument.ref);
    acceptedLedgerIds.push(ledgerId);
  }

  return acceptedLedgerIds;
}

async function ensureUserEmailIndex(auth, db) {
  const uid = auth.currentUser?.uid;
  const email = normalizeEmail(auth.currentUser?.email);
  if (!uid || !email) {
    return;
  }

  await setDoc(
    doc(db, "userEmails", email),
    {
      uid,
      email,
      displayName: auth.currentUser.displayName || email,
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

async function loadUserByEmail(db, email) {
  if (!email) {
    return null;
  }

  const userSnapshot = await getDoc(doc(db, "userEmails", email));
  if (!userSnapshot.exists()) {
    return null;
  }

  const user = userSnapshot.data();
  return {
    uid: user.uid || "",
    email: normalizeEmail(user.email) || email,
    displayName: user.displayName || "",
  };
}

async function grantLedgerAccess(db, ledgerId, member) {
  await updateDoc(doc(db, "ledgers", ledgerId), {
    memberUids: arrayUnion(member.uid),
    memberEmails: arrayUnion(normalizeEmail(member.email)),
    members: arrayUnion({
      uid: member.uid,
      email: normalizeEmail(member.email),
      displayName: member.displayName || normalizeEmail(member.email),
    }),
    invitedEmails: arrayRemove(normalizeEmail(member.email)),
    updatedAt: serverTimestamp(),
  });
  await setDoc(
    doc(db, "userLedgers", member.uid, "ledgers", ledgerId),
    {
      ledgerId,
      role: "member",
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

async function loadLedgerSummaries(auth, db) {
  const uid = auth.currentUser?.uid;
  if (!uid) {
    return [];
  }

  const membershipSnapshot = await getDocs(collection(db, "userLedgers", uid, "ledgers"));
  const summaries = [];
  for (const membershipDocument of membershipSnapshot.docs) {
    const ledgerId = membershipDocument.data().ledgerId || membershipDocument.id;
    const ledgerSnapshot = await getDoc(doc(db, "ledgers", ledgerId));
    if (ledgerSnapshot.exists()) {
      summaries.push(serializeLedgerSummary(ledgerSnapshot));
    } else {
      await deleteDoc(membershipDocument.ref);
    }
  }

  return summaries.sort((left, right) => left.name.localeCompare(right.name));
}

function emitCachedLedger(app, auth, ledgerId) {
  emitLedgerPayload(app, loadLedgerCache(auth.currentUser?.uid, ledgerId));
}

function emitLedgerPayload(app, payload) {
  if (payload) {
    app.ports.ledgerLoaded.send(payload);
  }
}

function emitLocalLedger(app, payload) {
  emitLedgerPayload(app, cacheLocalLedgerPayload(payload));
}

function ledgerCacheKey(uid, ledgerId) {
  return `contabilizar:ledger:${uid}:${ledgerId}`;
}

function defaultLocalLedgerPayload() {
  return {
    status: "loaded",
    ledgerId: LOCAL_LEDGER_ID,
    lastAccountId: loadLastAccountId(LOCAL_LEDGER_ID),
    ledgers: [
      {
        id: LOCAL_LEDGER_ID,
        name: DEFAULT_LOCAL_LEDGER_NAME,
        ownerUid: "",
        members: [],
        invitedEmails: [],
      },
    ],
    accounts: [],
    expenses: [],
    events: [],
    lastEventSequence: 0,
  };
}

function normalizeLocalLedgerPayload(payload) {
  const events = Array.isArray(payload?.events) ? payload.events : [];
  const accounts = Array.isArray(payload?.accounts) ? payload.accounts : [];
  const ledgerName =
    payload?.ledgers?.[0]?.name || payload?.ledgerName || DEFAULT_LOCAL_LEDGER_NAME;

  return {
    status: "loaded",
    ledgerId: LOCAL_LEDGER_ID,
    lastAccountId: loadLastAccountId(LOCAL_LEDGER_ID) || payload?.lastAccountId || null,
    ledgers: [
      {
        id: LOCAL_LEDGER_ID,
        name: ledgerName,
        ownerUid: "",
        members: [],
        invitedEmails: [],
      },
    ],
    accounts,
    expenses: [],
    events,
    lastEventSequence: computeLastEventSequence(events),
  };
}

function getLocalLedgerPayload() {
  return loadLocalLedgerCache() || defaultLocalLedgerPayload();
}

function hasLocalLedgerData(payload) {
  const ledgerName = payload?.ledgers?.[0]?.name || DEFAULT_LOCAL_LEDGER_NAME;
  return (
    (Array.isArray(payload?.events) && payload.events.length > 0) ||
    (Array.isArray(payload?.accounts) && payload.accounts.length > 0) ||
    ledgerName !== DEFAULT_LOCAL_LEDGER_NAME
  );
}

function cacheLocalLedgerPayload(payload) {
  const cachedPayload = normalizeLocalLedgerPayload(payload);

  try {
    localStorage.setItem(
      LOCAL_LEDGER_KEY,
      JSON.stringify({
        schemaVersion: LOCAL_LEDGER_SCHEMA_VERSION,
        updatedAt: new Date().toISOString(),
        payload: cachedPayload,
      }),
    );
  } catch (error) {
    console.warn("Could not cache local ledger data", error);
  }

  return cachedPayload;
}

function loadLocalLedgerCache() {
  try {
    const rawCache = localStorage.getItem(LOCAL_LEDGER_KEY);
    if (!rawCache) {
      return null;
    }

    const cache = JSON.parse(rawCache);
    if (
      cache?.schemaVersion !== LOCAL_LEDGER_SCHEMA_VERSION ||
      cache?.payload?.ledgerId !== LOCAL_LEDGER_ID
    ) {
      localStorage.removeItem(LOCAL_LEDGER_KEY);
      return null;
    }

    return normalizeLocalLedgerPayload(cache.payload);
  } catch (error) {
    console.warn("Could not load local ledger data", error);
    return null;
  }
}

function clearLocalLedgerCache() {
  try {
    localStorage.removeItem(LOCAL_LEDGER_KEY);
    localStorage.removeItem(lastAccountStorageKey(LOCAL_LEDGER_ID));
  } catch (error) {
    console.warn("Could not clear local ledger data", error);
  }
}

function defaultPersonalLedgerName(user) {
  const rawName = String(user?.displayName || user?.email || "").trim();
  const name = rawName || "desconocido";
  return `Libro contable de ${name}`;
}

function isDefaultLedgerName(name) {
  return (
    !name ||
    name === "Mi libro contable" ||
    name === DEFAULT_LOCAL_LEDGER_NAME ||
    name.startsWith("Libro contable de ")
  );
}

function computeLastEventSequence(events) {
  let maxSeq = 0;
  for (const event of events) {
    if (event.sequence > maxSeq) {
      maxSeq = event.sequence;
    }
  }
  return maxSeq;
}

function cacheLedgerPayload(uid, payload) {
  if (!uid || !payload?.ledgerId) {
    return payload;
  }

  const events = Array.isArray(payload.events) ? payload.events : [];
  const lastEventSequence = computeLastEventSequence(events);

  const cachedPayload = {
    status: "loaded",
    ledgerId: payload.ledgerId,
    lastAccountId: payload.lastAccountId || loadLastAccountId(payload.ledgerId),
    ledgers: Array.isArray(payload.ledgers) ? payload.ledgers : [],
    accounts: Array.isArray(payload.accounts) ? payload.accounts : [],
    expenses: Array.isArray(payload.expenses) ? payload.expenses : [],
    events,
    lastEventSequence,
  };

  try {
    localStorage.setItem(
      ledgerCacheKey(uid, payload.ledgerId),
      JSON.stringify({
        schemaVersion: LEDGER_CACHE_SCHEMA_VERSION,
        syncedAt: new Date().toISOString(),
        payload: cachedPayload,
      }),
    );
    saveLastSession(uid, payload.ledgerId);
  } catch (error) {
    console.warn("Could not cache ledger data", error);
  }

  return cachedPayload;
}

function loadLedgerCache(uid, ledgerId) {
  if (!uid || !ledgerId) {
    return null;
  }

  try {
    const rawCache = localStorage.getItem(ledgerCacheKey(uid, ledgerId));
    if (!rawCache) {
      return null;
    }

    const cache = JSON.parse(rawCache);
    if (
      cache?.schemaVersion !== LEDGER_CACHE_SCHEMA_VERSION ||
      cache?.payload?.ledgerId !== ledgerId
    ) {
      localStorage.removeItem(ledgerCacheKey(uid, ledgerId));
      return null;
    }

    return {
      ...cache.payload,
      lastAccountId: loadLastAccountId(ledgerId) || cache.payload.lastAccountId || null,
    };
  } catch (error) {
    console.warn("Could not load cached ledger data", error);
    return null;
  }
}

function loadStartupLedgerCache() {
  try {
    const localLedger = loadLocalLedgerCache();
    if (hasLocalLedgerData(localLedger)) {
      return localLedger;
    }

    const sessionLedger = loadLastSessionLedgerCache();
    if (sessionLedger) {
      return sessionLedger;
    }

    return loadMostRecentLedgerCache();
  } catch (error) {
    console.warn("Could not load startup ledger cache", error);
    return null;
  }
}

function loadLastSessionLedgerCache() {
  const rawSession = localStorage.getItem(LAST_SESSION_KEY);
  if (!rawSession) {
    return null;
  }

  const session = JSON.parse(rawSession);
  return loadLedgerCache(session?.uid, session?.ledgerId);
}

function loadMostRecentLedgerCache() {
  let latest = null;
  let latestSyncedAt = "";
  const keyPrefix = "contabilizar:ledger:";

  for (let index = 0; index < localStorage.length; index += 1) {
    const key = localStorage.key(index);
    if (!key?.startsWith(keyPrefix)) {
      continue;
    }

    try {
      const cache = JSON.parse(localStorage.getItem(key));
      if (
        cache?.schemaVersion !== LEDGER_CACHE_SCHEMA_VERSION ||
        cache?.payload?.status !== "loaded" ||
        !cache?.payload?.ledgerId
      ) {
        continue;
      }

      const syncedAt = String(cache.syncedAt || "");
      if (!latest || syncedAt > latestSyncedAt) {
        latest = cache.payload;
        latestSyncedAt = syncedAt;
      }
    } catch (error) {
      console.warn("Could not inspect cached ledger", key, error);
    }
  }

  if (!latest) {
    return null;
  }

  return {
    ...latest,
    lastAccountId: loadLastAccountId(latest.ledgerId) || latest.lastAccountId || null,
  };
}

function saveLastSession(uid, ledgerId) {
  if (!uid || !ledgerId) {
    return;
  }

  try {
    localStorage.setItem(LAST_SESSION_KEY, JSON.stringify({ uid, ledgerId }));
  } catch (error) {
    console.warn("Could not save last session", error);
  }
}

function clearLastSession() {
  try {
    localStorage.removeItem(LAST_SESSION_KEY);
  } catch (error) {
    console.warn("Could not clear last session", error);
  }
}

function loadTutorialState() {
  try {
    return localStorage.getItem(TUTORIAL_STATE_KEY) || "";
  } catch (error) {
    console.warn("Could not load tutorial state", error);
    return "";
  }
}

function saveTutorialState(state) {
  try {
    localStorage.setItem(TUTORIAL_STATE_KEY, String(state || ""));
  } catch (error) {
    console.warn("Could not save tutorial state", error);
  }
}

function loadFilterWindow() {
  try {
    return localStorage.getItem(FILTER_WINDOW_KEY) || "complete";
  } catch (error) {
    console.warn("Could not load filter window", error);
    return "complete";
  }
}

function saveFilterWindow(filterWindow) {
  try {
    localStorage.setItem(FILTER_WINDOW_KEY, String(filterWindow || "complete"));
  } catch (error) {
    console.warn("Could not save filter window", error);
  }
}

function loadColorScheme() {
  const fallback =
    window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";

  try {
    return localStorage.getItem(COLOR_SCHEME_KEY) || fallback;
  } catch (error) {
    console.warn("Could not load color scheme", error);
    return fallback;
  }
}

function saveColorScheme(colorScheme) {
  try {
    localStorage.setItem(COLOR_SCHEME_KEY, String(colorScheme || "light"));
  } catch (error) {
    console.warn("Could not save color scheme", error);
  }
}

function applyColorScheme(colorScheme) {
  const normalized = colorScheme === "dark" ? "dark" : "light";
  document.documentElement.dataset.theme = normalized;
  document.documentElement.style.colorScheme = normalized;
}

function exchangeRateCacheKey(uid, ledgerId, casa, date) {
  const scope = uid ? `${uid}:${ledgerId}` : `local:${ledgerId || LOCAL_LEDGER_ID}`;
  return `contabilizar:exchangeRate:${scope}:${casa}:${date}`;
}

function exchangeRateDocumentId(casa, date) {
  return `${casa}-${date}`;
}

function cacheExchangeRate(uid, ledgerId, casa, date, sale) {
  const normalizedSale = Number(sale);
  if (!Number.isFinite(normalizedSale) || normalizedSale <= 0) {
    return null;
  }

  const entry = {
    casa: String(casa || "bolsa"),
    date: String(date || ""),
    sale: normalizedSale,
  };

  try {
    localStorage.setItem(
      exchangeRateCacheKey(uid, ledgerId, entry.casa, entry.date),
      JSON.stringify({
        schemaVersion: EXCHANGE_RATE_CACHE_SCHEMA_VERSION,
        cachedAt: new Date().toISOString(),
        payload: entry,
      }),
    );
  } catch (error) {
    console.warn("Could not cache exchange rate", error);
  }

  return entry;
}

function loadExchangeRateCache(uid, ledgerId, casa, date) {
  try {
    const rawEntry = localStorage.getItem(exchangeRateCacheKey(uid, ledgerId, casa, date));
    if (!rawEntry) {
      return null;
    }

    const cache = JSON.parse(rawEntry);
    if (
      cache?.schemaVersion !== EXCHANGE_RATE_CACHE_SCHEMA_VERSION ||
      cache?.payload?.casa !== casa ||
      cache?.payload?.date !== date
    ) {
      localStorage.removeItem(exchangeRateCacheKey(uid, ledgerId, casa, date));
      return null;
    }

    const sale = Number(cache.payload.sale);
    if (!Number.isFinite(sale) || sale <= 0) {
      return null;
    }

    return {
      casa,
      date,
      sale,
    };
  } catch (error) {
    console.warn("Could not load cached exchange rate", error);
    return null;
  }
}

async function fetchHistoricalExchangeRateFromApi(casa, date) {
  const [year, month, day] = String(date || "").split("-");
  if (!year || !month || !day) {
    throw new Error("La fecha histórica no es válida.");
  }

  const response = await fetch(
    `https://api.argentinadatos.com/v1/cotizaciones/dolares/${encodeURIComponent(casa)}/${encodeURIComponent(year)}/${encodeURIComponent(month)}/${encodeURIComponent(day)}`,
  );

  if (!response.ok) {
    throw new Error(`La API histórica devolvió ${response.status}.`);
  }

  const payload = await response.json();
  const sale = Number(payload?.venta);
  if (!Number.isFinite(sale) || sale <= 0) {
    throw new Error("La API histórica no devolvió una venta válida.");
  }

  return sale;
}

async function fetchLiveExchangeRateFromApi(casa) {
  const response = await fetch(
    `https://dolarapi.com/v1/ambito/dolares/${encodeURIComponent(casa)}`,
  );

  if (!response.ok) {
    throw new Error(`La API en vivo devolvió ${response.status}.`);
  }

  const payload = await response.json();
  const sale = Number(payload?.venta);
  if (!Number.isFinite(sale) || sale <= 0) {
    throw new Error("La API en vivo no devolvió una venta válida.");
  }

  return sale;
}

function todayIsoDate() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function isToday(date) {
  return String(date || "") === todayIsoDate();
}

function exchangeRateErrorMessage(error, date) {
  const details = String(error?.message || "").trim();
  return `No se pudo cargar la cotización bolsa del ${date}.${details ? ` ${details}` : ""}`.trim();
}

function updateLedgerCache(uid, ledgerId, updatePayload) {
  const payload = loadLedgerCache(uid, ledgerId);
  if (!payload) {
    return null;
  }

  return cacheLedgerPayload(uid, updatePayload(payload));
}

function upsertCachedAccount(uid, ledgerId, account) {
  return updateLedgerCache(uid, ledgerId, (payload) => ({
    ...payload,
    accounts: upsertById(payload.accounts, account),
  }));
}

function softDeleteCachedAccount(uid, ledgerId, accountId, deletedAt) {
  return updateLedgerCache(uid, ledgerId, (payload) => ({
    ...payload,
    accounts: payload.accounts.map((account) =>
      account.id === accountId ? { ...account, deletedAt } : account,
    ),
    expenses: payload.expenses.map((expense) =>
      expense.accountId === accountId && !expense.deletedAt ? { ...expense, deletedAt } : expense,
    ),
  }));
}

function upsertById(items, item) {
  const id = String(item.id || "");
  const index = items.findIndex((candidate) => String(candidate.id || "") === id);

  if (index === -1) {
    return [item, ...items];
  }

  return items.map((candidate, candidateIndex) => (candidateIndex === index ? item : candidate));
}

function lastAccountStorageKey(ledgerId) {
  return `contabilizar:lastAccount:${ledgerId}`;
}

function saveLastAccountId(ledgerId, accountId) {
  if (!ledgerId || !accountId) {
    return;
  }

  try {
    localStorage.setItem(lastAccountStorageKey(ledgerId), accountId);
  } catch (error) {
    console.warn("Could not save last account selection", error);
  }
}

function loadLastAccountId(ledgerId) {
  if (!ledgerId) {
    return null;
  }

  try {
    return localStorage.getItem(lastAccountStorageKey(ledgerId));
  } catch (error) {
    console.warn("Could not load last account selection", error);
    return null;
  }
}

function serializeLedgerSummary(documentSnapshot) {
  const data = documentSnapshot.data();
  return {
    id: String(data.id || documentSnapshot.id),
    name: data.name || "Libro contable",
    ownerUid: data.ownerUid || "",
    members: Array.isArray(data.members) ? data.members.map(serializeMember) : [],
    invitedEmails: Array.isArray(data.invitedEmails)
      ? data.invitedEmails.map(normalizeEmail).filter(Boolean)
      : [],
  };
}

function serializeMember(member) {
  return {
    uid: member.uid || "",
    email: normalizeEmail(member.email),
    displayName: member.displayName || "",
  };
}

function serializeFirestoreDocument(documentSnapshot) {
  const data = documentSnapshot.data();
  return {
    ...data,
    id: String(data.id || documentSnapshot.id),
    deletedAt: serializeMaybeTimestamp(data.deletedAt),
  };
}

function serializeMaybeTimestamp(value) {
  if (!value) {
    return null;
  }

  if (typeof value === "string") {
    return value;
  }

  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }

  return String(value);
}

function normalizeEmail(email) {
  return String(email || "")
    .trim()
    .toLowerCase();
}

function uuidv7() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);

  let timestamp = BigInt(Date.now());
  for (let index = 5; index >= 0; index -= 1) {
    bytes[index] = Number(timestamp & 0xffn);
    timestamp >>= 8n;
  }

  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function serializeUser(user, acceptedInviteLedgerId = null) {
  return {
    uid: user.uid || "",
    displayName: user.displayName || "",
    email: user.email || "",
    photoUrl: user.photoURL || "",
    acceptedInviteLedgerId,
  };
}

function firebaseAuthErrorMessage(error) {
  const code = error?.code || "auth/unknown";
  const message = error?.message || "Sin detalle técnico.";

  if (code === "auth/popup-closed-by-user") {
    return "Se cerró la ventana de ingreso.";
  }

  if (code === "auth/unauthorized-domain") {
    return "Dominio no autorizado en Firebase Auth: " + window.location.hostname;
  }

  if (code === "auth/operation-not-allowed") {
    return "Google no está habilitado en Firebase Auth.";
  }

  if (code === "auth/popup-blocked") {
    return "El navegador bloqueó la ventana de ingreso.";
  }

  return `No se pudo iniciar sesión con Google (${code}): ${message}`;
}

function firestoreErrorMessage(error) {
  const code = error?.code || "firestore/unknown";
  const message = error?.message || "Sin detalle técnico.";

  if (code === "permission-denied") {
    return "Firestore rechazó el acceso a este libro contable.";
  }

  if (code === "unavailable") {
    return "Firestore no está disponible en este momento.";
  }

  return `No se pudieron sincronizar los datos (${code}): ${message}`;
}
