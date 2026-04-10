# Offline Sync + Flexible QR Parsing Implementation Summary

## ✅ Status: Ready for Testing

All critical features have been implemented and integrated. The app now supports:
1. **Offline-first synchronization** - writes go to local SQLite, sync happens when connection is available
2. **Flexible QR parsing** - handles JSON, URL params, key=value, delimited formats, and plain text
3. **Web compatibility** - graceful degradation on web (uses Firestore directly), full offline sync on mobile/desktop

---

## 📋 Files Created/Modified

### New Files Created:

#### `lib/core/utils/qr_parser.dart`
- **Purpose**: Flexible QR format parser supporting multiple input formats
- **Features**:
  - JSON parsing (primary format)
  - URL query parameters
  - Key-value pairs (& or ; separated)
  - Pipe-delimited or tab-delimited values
  - Plain text fallback
  - Field alias mapping (customer→nombre, cuit→dni, etc.)
  - Handles your specific QR format with integer orderId
- **Key Methods**:
  - `parse()` - main entry point, tries all formats
  - `toDeliveryJson()` - converts to Delivery-compatible JSON
  - Field mapping supports 30+ common field aliases

#### `lib/core/data/local_database.dart`
- **Purpose**: SQLite local database for offline storage
- **Features**:
  - Two tables: `deliveries` (main data) and `pending_sync` (operation queue)
  - Proper date serialization (ISO 8601 strings)
  - List JSON serialization (for evidences)
  - Web-safe: returns early with no-op on web (kIsWeb check)
  - Automatic schema upgrade from v1→v2
  - Indexes on conductorId and orderId for fast queries
- **Key Methods**:
  - `upsertDelivery()`, `getDeliveriesByDriver()`, `getDeliveryById()`
  - `addPendingSync()` - queue operations for later
  - `getPendingSyncs()`, `removePendingSync()` - manage retry queue
  - `cleanupFailedSyncs()` - remove items after max retries

#### `lib/core/data/sync_service.dart`
- **Purpose**: Orchestrates offline-first sync strategy
- **Features**:
  - Local-first pattern: writes to SQLite first, then Firestore
  - Connectivity monitoring with automatic retry on reconnection
  - `SyncStatus` enum: online, offline, syncing
  - Pending operation queue with retry logic (max 10 attempts)
  - Periodic retry timer (every 2 minutes) for mobile/desktop
  - Web fallback: direct Firestore queries when local DB unavailable
  - `ValueNotifier` for reactive UI updates
- **Key Methods**:
  - `createDelivery()`, `updateDelivery()`, `deleteDelivery()` - write operations
  - `getDeliveriesByDriver()`, `getDeliveryById()` - read operations with sync
  - `fullSync()` - force complete sync from Firestore
  - Status and pending count are observable via ValueNotifier

### Modified Files:

#### `lib/features/scan_qr/presentation/scan_qr_screen.dart`
- **Line 150-151**: Fixed orderId handling:
  ```dart
  final rawOrderId = json['orderId'];
  final orderIdFromJson = rawOrderId == null ? '' : rawOrderId.toString().trim();
  ```
  - Handles both int and string orderId values from QR
  - Your QR format with `"orderId": 173837` now works correctly

#### `lib/features/delivery/data/delivery_repository.dart`
- **Line 123**: `createDelivery()` → routes through `SyncService.instance.createDelivery()`
- **Line 377**: `getDeliveriesByDriver()` → routes through `SyncService` with Firestore fallback
- **Line 405**: `updateDelivery()` → routes through `SyncService`
- All write operations now use local-first pattern

#### `lib/features/home/presentation/home_screen.dart`
- **Lines 47-101**: Sync status indicator in AppBar
  - Shows cloud_done (synced), cloud_off (offline), or sync (syncing) icon
  - Displays pending count when offline
  - Tap to manually trigger sync if items pending
- **Line 29**: Calls `fullSync()` on screen init to pull latest Firestore data

#### `lib/main.dart`
- **Line 17**: `await LocalDatabase.instance.init();`
- **Line 18**: `await SyncService.instance.init();`
- Initializes offline infrastructure before app runs

#### `windows/CMakeLists.txt`
- **Line 42**: Added `/wd"4996"` flag
  - Suppresses C4996 warning from Firebase C++ SDK's deprecated strncpy
  - Allows Windows desktop build to complete

#### `pubspec.yaml`
- **Line 49**: `sqflite: ^2.4.1` - SQLite database
- **Line 50**: `path_provider: ^2.1.5` - file system paths
- **Line 51**: `connectivity_plus: ^6.1.3` - network connectivity monitoring

---

## 🔄 How It Works: Offline-First Pattern

### Write Operations (Create/Update/Delete):
```
User Action
    ↓
SyncService.createDelivery()
    ├─ Save to SQLite (immediate)
    └─ If online:
        ├─ Sync to Firestore
        └─ If fails: enqueue in pending_sync
       If offline:
        └─ Enqueue in pending_sync
```

### Read Operations:
**Mobile/Desktop:**
```
getDeliveriesByDriver()
    ├─ Try: Read from SQLite (immediate response)
    ├─ If online: Background sync from Firestore
    └─ Return local data
```

**Web:**
```
getDeliveriesByDriver()
    └─ Try/Catch: 
        ├─ Try: Read from SQLite (fails on web)
        └─ Catch: Query Firestore directly
```

### Pending Sync Processing:
```
Connection Restored
    ↓
_processPendingSyncs()
    ├─ Read all pending operations from SQLite
    ├─ For each operation (create/update/delete):
    │   ├─ Execute Firestore operation
    │   ├─ If success: remove from pending_sync
    │   └─ If fails: increment retry_count
    └─ Clean up items with >10 retries
```

### Connectivity Monitoring:
- **Mobile/Desktop**: `connectivity_plus` monitors WiFi/mobile/ethernet
- **Web**: Disabled (uses Firestore directly)
- **Auto-Retry**: Every 2 minutes, attempts to process pending syncs
- **Reconnection**: Immediately processes pending when connection restored

---

## 🎯 QR Format Support

Your specific QR format is fully supported:
```json
{
  "orderId": 173837,
  "nombre": "Diego Minutillo ",
  "telefono": "11-34842076",
  "dni": "25396690",
  "direccion": "Luis viale 1174 2 B",
  "codigoPostal": "1180",
  "localidad": "Almagro",
  "provincia": null,
  "observaciones": null
}
```

The parser also handles:
- **URL format**: `https://example.com?nombre=X&dni=Y&...`
- **Key-value format**: `nombre=X&dni=Y&direccion=Z`
- **Delimited format**: `X|Y|Z` (pipe or tab separated)
- **Plain text**: Falls back to editing form

---

## ⚙️ Configuration Points

### Retry Settings (`local_database.dart`):
- **Max Retries**: 10 (configurable in `cleanupFailedSyncs()`)
- **Failed items** >10 retries are automatically removed

### Sync Timing (`sync_service.dart`):
- **Periodic retry**: Every 2 minutes (mobile/desktop only)
- **Web**: No local database, direct Firestore access

### Database Location (`local_database.dart`):
- **Mobile/Desktop**: `{AppDocumentsDir}/acuaflex_deliveries.db`
- **Web**: N/A (uses Firestore directly)

---

## 🧪 Testing Checklist

### Browser Testing (Chrome/Web):
- [ ] QR scanning with your format works (no Future.catchError error)
- [ ] Cloud icon shows "sincronizado" when synced
- [ ] UI shows cloud_done icon with green checkmark

### Mobile Testing (with offline):
- [ ] Scan QR while online → delivery saves locally + syncs
- [ ] Turn off WiFi/mobile → icon changes to cloud_off
- [ ] Scan QR while offline → saved locally, icon shows pending count
- [ ] Turn on WiFi → pending icon shows progress, then cloud_done
- [ ] Check local DB file exists: `/sdcard/Android/data/com.example.acuaflex/files/acuaflex_deliveries.db`

### Edge Cases:
- [ ] Edit incomplete QR data in dialog, save, verify it syncs
- [ ] Multiple deliveries while offline, verify all sync on reconnection
- [ ] Duplicate orderId handling with multiple conductores
- [ ] Photos/signature data persists through offline cycle

---

## 🚀 Next Steps

1. **Test on Chrome**: Run `flutter run -d chrome` and scan your QR
2. **Test on Mobile**: Build and test offline sync on Android/iOS
3. **Monitor Logs**: Check `[SYNC]` debug output in console
4. **Verify Pending Queue**: Check SQLite pending_sync table when offline

The implementation handles all scenarios you requested:
- ✅ Offline sync prevents data loss
- ✅ Flexible QR parsing accepts your format without modification
- ✅ Cross-platform support (web, mobile, desktop)
- ✅ Graceful degradation on unsupported platforms
