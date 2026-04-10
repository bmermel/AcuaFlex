# Testing Guide: Offline Sync & Flexible QR Parsing

## Quick Start

### 1. Clean & Rebuild
```bash
flutter clean
flutter pub get
flutter pub upgrade
```

### 2. Test on Chrome (Web)
```bash
flutter run -d chrome
```

Expected behavior:
- App loads without `Future.catchError` errors
- QR scanner appears
- Sync status icon shows in top-right of AppBar

### 3. Test Your Specific QR Format
Scan this QR (or adjust values):
```json
{"orderId":173837,"nombre":"Diego Minutillo ","telefono":"11-34842076","dni":"25396690","direccion":"Luis viale 1174 2 B","codigoPostal":"1180","localidad":"Almagro","provincia":null,"observaciones":null}
```

Expected result:
- ✅ No crash
- ✅ Delivery loaded with all fields populated
- ✅ `nombre`, `dni`, `direccion` filled from QR
- ✅ `orderId` shown as "173837" (converted from integer)
- ✅ Cloud icon in AppBar shows "sincronizado"

---

## Detailed Testing Scenarios

### Scenario A: Basic QR Scanning (Chrome)
**Setup**: Running on Chrome, online

**Steps**:
1. Navigate to "Escanear QR" menu
2. Allow camera access
3. Scan your QR code
4. Observe delivery is created

**Expected**:
- Delivery appears in "Mis entregas"
- Cloud icon shows green checkmark
- No errors in console

**Log output should show**:
```
[SYNC] Processing pending syncs (if any)
[SCAN_QR] rawValue length=... orderId="173837" hasOrderId=true
[SYNC] Synced: create <deliveryId>
```

---

### Scenario B: Offline Sync (Mobile/Desktop)

**Setup**: Running on Android, iOS, or Windows

**Steps**:
1. Open app (connected to internet)
2. Scan a QR → delivery saves
3. Turn OFF WiFi (or use Airplane mode)
4. Scan another QR
5. Observe pending count increases
6. Turn WiFi back ON
7. Watch pending items sync automatically

**Expected**:
- When offline: Cloud icon shows cloud_off, displays pending count
- When online: Icon returns to cloud_done, pending count zeros
- Both deliveries appear in list after sync
- Check Console: `[SYNC] Processing X pending syncs`, then `[SYNC] Synced`

**Database verification** (Android):
```bash
adb shell
cd /sdcard/Android/data/com.example.acuaflex/files/
sqlite3 acuaflex_deliveries.db
SELECT COUNT(*) FROM deliveries;
SELECT COUNT(*) FROM pending_sync;
```

---

### Scenario C: Incomplete QR Data

**Test QR** (missing direccion):
```json
{"orderId":12345,"nombre":"Test Cliente","telefono":"123456789","dni":"12345678"}
```

**Steps**:
1. Scan incomplete QR
2. Edit dialog should appear
3. Fill in missing "Dirección" field
4. Tap save/confirm

**Expected**:
- Dialog appears with form
- Saved delivery shows complete data
- Syncs successfully

---

### Scenario D: Sync Status Indicator

**Cloud Icon States**:

| Icon | Meaning | Next Action |
|------|---------|------------|
| ☁️ ✓ | Synced, online, 0 pending | Nothing needed |
| ☁️ ✗ | Offline, X pending | Will auto-sync on reconnection |
| ⟳ | Syncing in progress | Wait for completion |

**Testing**:
1. Scan delivery while online → icon shows ☁️ ✓
2. Turn offline → icon shows ☁️ ✗ with pending count
3. Tap icon → shows status message
4. Turn online → icon animates to ⟳, then ☁️ ✓

---

### Scenario E: Multiple QR Formats

Test each format to verify parser handles all:

**Format 1: Pure JSON** (your format)
```json
{"orderId":1,"nombre":"John","dni":"123","direccion":"Calle 1"}
```

**Format 2: URL Parameters**
```
https://delivery.app?nombre=John&dni=123&direccion=Calle%201&orderId=2
```

**Format 3: Key-Value Pairs**
```
nombre=John&dni=123&direccion=Calle 1&orderId=3
```

**Format 4: Pipe-Delimited**
```
John|123|Calle 1|555-1234|Obs
```

**Format 5: Plain Text**
```
Entrega urgente a John
```

**Expected**:
- All formats parse without errors
- JSON format (yours) takes priority
- Field mapping works correctly
- Plain text goes to observaciones, shows edit dialog

---

## Console Debugging

### Enable Debug Logging
Logs show in `flutter run` console with these prefixes:

```
[SYNC]          → Sync service events
[LOCAL_DB]      → Database operations
[SCAN_QR]       → QR parsing and detection
```

### Key Log Messages

**Expected during QR scan**:
```
[SCAN_QR] QR parsed with flexible parser parseMethod=json
[SCAN_QR] rawValue length=XXX orderId="173837" hasOrderId=true
[SYNC] SyncService initialized, status: online
```

**Expected when offline → online**:
```
[SYNC] Connection lost
[SYNC] Queuing operation: create for <deliveryId>
[SYNC] Connection restored, will process pending syncs
[SYNC] Processing 1 pending syncs
[SYNC] Synced: create <deliveryId>
```

**Watch for errors**:
```
[SYNC] Failed to sync create: <error>
[LOCAL_DB] Failed to initialize: <error>
Future.catchError  → Should NOT appear (fixed in sync_service.dart)
```

---

## Windows Build Verification

If building for Windows Desktop:

```bash
flutter run -d windows
```

Should compile without:
- ❌ `error C2228: left of '.la_siguleint' must have class/struct/union`
- ❌ Unresolved external symbol errors

If you see these, verify `windows/CMakeLists.txt` line 42 has:
```cmake
target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100" /wd"4996")
```

---

## Troubleshooting

### Issue: "Future.catchError must return a value of the future's type"
**Solution**: This error is fixed in `sync_service.dart` with try/catch blocks on web.
- Verify you're using latest `sync_service.dart` from this session
- Check that `SyncService.instance.getDeliveriesByDriver()` has try/catch (line 201)

### Issue: "MissingPluginException: No implementation found for method getApplicationDocumentsDirectory"
**Cause**: Running on web, where path_provider doesn't work
**Solution**: Already handled - `LocalDatabase.init()` checks `kIsWeb` and returns early
- Web uses Firestore directly, no local database
- Mobile/Desktop use SQLite

### Issue: Cloud icon stuck on syncing ⟳
**Solution**:
1. Check console for `[SYNC] Failed to sync` errors
2. Verify Firestore is accessible
3. Check internet connection
4. Restart app

### Issue: "No deliveries found" after offline sync
**Debug**:
1. Check if `pending_sync` table has items (offline)
2. Turn online and wait 5 seconds
3. Check console for `[SYNC] Processing X pending syncs`
4. Verify `deliveries` table has new rows

---

## Performance Notes

### Sync Performance
- **Cold start**: ~100-500ms (first local query)
- **Background sync**: <1s (querying Firestore in background)
- **Large offline queue**: If >50 pending items, expect 3-5 seconds to process

### Database Performance
- **SQLite queries**: <10ms for typical driver (100-1000 deliveries)
- **Firestore queries**: 200-500ms (network latency)

### Optimization Tips
- On slow connections, pending syncs retry every 2 minutes (configurable in `sync_service.dart`)
- If many offline deliveries, sync happens in batches (configurable)
- Web users always hit Firestore (no local storage advantage)

---

## Final Verification Checklist

Before considering offline sync complete, verify:

- [ ] QR scans and parses without crashes (all formats)
- [ ] Your specific orderId format (integer) works
- [ ] Sync indicator appears in AppBar
- [ ] Offline detection works (WiFi toggle shows effect)
- [ ] Pending items sync on reconnection (manual or auto)
- [ ] Console shows `[SYNC]` messages, no `Future.catchError` errors
- [ ] Windows build succeeds (if building for Windows)
- [ ] Multiple deliveries can be saved offline and sync together
- [ ] Edit dialog appears for incomplete QR data
- [ ] Both platforms work: web (Firestore direct) and mobile (SQLite+Firestore)

Once all above pass, offline sync is working correctly.
