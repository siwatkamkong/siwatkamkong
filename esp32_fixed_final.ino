// ESP32 Table System with HTTP Server - สำหรับรีเลย์ 4CH 3 ตัว (12 channels)
// รีเลย์ 4CH 3 ตัว = 12 channels สำหรับปุ่มเพจเจอร์
// 
// Layout ปุ่มเพจเจอร์:
//   1  2  3  ลบ
//   4  5  6  0
//   7  8  9  call
// 
// การเชื่อมต่อรีเลย์ 4CH 3 ตัว:
// - รีเลย์ตัวที่ 1: IN1-IN4 → ปุ่ม 1, 2, 3, ลบ
// - รีเลย์ตัวที่ 2: IN1-IN4 → ปุ่ม 4, 5, 6, 0
// - รีเลย์ตัวที่ 3: IN1-IN4 → ปุ่ม 7, 8, 9, call
//
// การใช้งานจากแอพ:
// เมื่อแอดมินกดปุ่ม "เรียกโต๊ะ" ในแอพ แอพจะส่ง HTTP GET request ไปที่:
//   http://<ESP32_IP>/buzz?id=<หมายเลขโต๊ะ>
// เช่น: http://192.168.1.100/buzz?id=5
// ESP32 จะรับคำสั่งและกดปุ่มเพจเจอร์อัตโนมัติ:
//   1. กดเลขตามหมายเลขโต๊ะ (เช่น 5 → กดปุ่ม 5)
//   2. กดปุ่ม CALL เพื่อเรียกเพจเจอร์
// 
// ตัวอย่าง: เรียกโต๊ะหมายเลข 12
//   - กดปุ่ม 1
//   - กดปุ่ม 2
//   - กดปุ่ม CALL
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <ESPmDNS.h> 
// การตั้งค่า WiFi
// เลือกโหมด: true = Access Point (Hotspot), false = Client (เชื่อมต่อ WiFi หลัก)
const bool USE_AP_MODE = false;  // ตั้งเป็น false เพื่อเชื่อมต่อ WiFi หลัก (มีอินเทอร์เน็ต)


// การตั้งค่า WiFi Hotspot (Access Point) - ใช้เมื่อ USE_AP_MODE = true
const char* ap_ssid = "Siwat";     // ชื่อ WiFi Hotspot
const char* ap_password = "1234567891";            // รหัสผ่าน WiFi Hotspot (อย่างน้อย 8 ตัวอักษร)
const IPAddress local_IP(192, 168, 4, 1);       // IP address ของ ESP32 (default สำหรับ AP mode)
const IPAddress gateway(192, 168, 4, 1);        // Gateway
const IPAddress subnet(255, 255, 255, 0);       // Subnet mask


// การตั้งค่า WiFi Client (เชื่อมต่อ WiFi หลัก) - ใช้เมื่อ USE_AP_MODE = false
const char* wifi_ssid = "DISATM";           // ชื่อ WiFi หลัก
const char* wifi_password = "88888888";       // รหัสผ่าน WiFi หลัก

// การตั้งค่า Firebase Firestore (ใช้ REST API)
// Project ID: project-fire-baseaapp
const char* firebaseProjectId = "project-fire-baseaapp";  // Project ID จาก Firebase
const char* firebaseApiKey = "AIzaSyBizJ09pQO3IYmBBRoPMdxUtJMZLlGE_Ss";  // API Key จาก Firebase
const bool enableFirestore = true;  // เปิดการตรวจสอบ Firestore (ใช้เมื่อ ESP32 เชื่อมต่อ WiFi หลัก)
const unsigned long firestoreCheckInterval = 3000;  // ตรวจสอบ Firestore ทุก 3 วินาที
unsigned long lastFirestoreCheck = 0;
String lastProcessedCommandId = "";  // เก็บ ID ของคำสั่งที่ประมวลผลแล้ว

// การตั้งค่ารีเลย์ 5V
// รีเลย์ 4CH 5V ส่วนใหญ่เป็น Active LOW (LOW=กด, HIGH=ปล่อย)
// ถ้ารีเลย์ติดทุกตัวเมื่อเริ่มต้น ให้เปลี่ยนเป็น true
const bool ACTIVE_LOW = true;   // true = Active LOW (LOW=กด, HIGH=ปล่อย)
                                 // false = Active HIGH (HIGH=กด, LOW=ปล่อย)

// GPIO pins สำหรับปุ่มเพจเจอร์ (12 pins สำหรับรีเลย์ 4CH 3 ตัว)
// รีเลย์ตัวที่ 1 (ปุ่มแถวบน): 1, 2, 3, ลบ
const int PIN_1 = 2;         // ปุ่ม 1
const int PIN_2 = 4;         // ปุ่ม 2
const int PIN_3 = 5;         // ปุ่ม 3
const int PIN_BACKSPACE = 18; // ปุ่มลบ

// รีเลย์ตัวที่ 2 (ปุ่มแถวกลาง): 4, 5, 6, 0
const int PIN_4 = 19;        // ปุ่ม 4
const int PIN_5 = 21;        // ปุ่ม 5
const int PIN_6 = 22;        // ปุ่ม 6
const int PIN_0 = 23;        // ปุ่ม b


// รีเลย์ตัวที่ 3 (ปุ่มแถวล่าง): 7, 8, 9, call
const int PIN_7 = 25;        // ปุ่ม 7
const int PIN_8 = 26;        // ปุ่ม 8
const int PIN_9 = 27;        // ปุ่ม 9
const int PIN_CALL = 32;     // ปุ่ม call

// Array สำหรับการกดเลข 0-9 (เรียงตามตัวเลข)
int DIGIT_PINS[10] = {
  PIN_0,  // 0
  PIN_1,  // 1
  PIN_2,  // 2
  PIN_3,  // 3
  PIN_4,  // 4
  PIN_5,  // 5
  PIN_6,  // 6
  PIN_7,  // 7
  PIN_8,  // 8
  PIN_9   // 9
};

// การตั้งค่าเวลา
// การตั้งค่าเวลา
int PRESS_DURATION = 800;   // กดค้าง 1 วินาที
int DELAY_BETWEEN  = 800;    // หน่วงระหว่างปุ่ม (ปรับได้)


// HTTP Server
WebServer server(80);


void setup() {
  Serial.begin(115200);
  
  // ตั้งค่า GPIO pins ทั้งหมด 12 pins (รีเลย์ 4CH 3 ตัว)
  // ปุ่มเลข 0-9
  for (int i = 0; i < 10; i++) {
    pinMode(DIGIT_PINS[i], OUTPUT);
    // ตั้งค่า initial state = ปล่อย (ไม่กด)
    // ถ้า ACTIVE_LOW = true: HIGH = ปล่อย, LOW = กด
    // ถ้า ACTIVE_LOW = false: LOW = ปล่อย, HIGH = กด
    digitalWrite(DIGIT_PINS[i], ACTIVE_LOW ? HIGH : LOW);
  }
  
  // ปุ่ม CALL
  pinMode(PIN_CALL, OUTPUT);
  digitalWrite(PIN_CALL, ACTIVE_LOW ? HIGH : LOW);
  
  // ปุ่ม BACKSPACE (ลบ)
  pinMode(PIN_BACKSPACE, OUTPUT);
  digitalWrite(PIN_BACKSPACE, ACTIVE_LOW ? HIGH : LOW);
  
  // รอให้รีเลย์ settle
  delay(100);
  
  Serial.println("All relays initialized to OFF state");

  Serial.println("\n=== ESP32 Table System with HTTP Server ===");
  Serial.println("Version: 4CH Relay x3 (12 channels)");
  Serial.println("Relay Type: 5V 4CH x 3 units");
  Serial.println("Active Low: " + String(ACTIVE_LOW ? "true" : "false"));
  Serial.println("Total Channels: 12 (ปุ่มเพจเจอร์ทั้งหมด)");
  
  if (USE_AP_MODE) {
    // สร้าง WiFi Hotspot (Access Point)
    Serial.println("\n=== Creating WiFi Hotspot ===");
    Serial.print("SSID: ");
    Serial.println(ap_ssid);
    Serial.print("Password: ");
    Serial.println(ap_password);
    
    // ตั้งค่า IP address สำหรับ AP mode
    if (!WiFi.softAPConfig(local_IP, gateway, subnet)) {
      Serial.println("Failed to configure AP IP address");
    }
    
    // สร้าง WiFi Access Point
    bool ap_started = WiFi.softAP(ap_ssid, ap_password);
    
    if (ap_started) {
      Serial.println("✅ WiFi Hotspot created successfully!");
      Serial.print("IP address: ");
      Serial.println(WiFi.softAPIP());
      Serial.print("MAC address: ");
      Serial.println(WiFi.softAPmacAddress());
      Serial.println("\n📱 Connect your phone to WiFi:");
      Serial.print("   SSID: ");
      Serial.println(ap_ssid);
      Serial.print("   Password: ");
      Serial.println(ap_password);
      Serial.print("   Then access: http://");
      Serial.println(WiFi.softAPIP());
      Serial.println("⚠️ Note: No internet connection in AP mode");
    } else {
      Serial.println("❌ Failed to create WiFi Hotspot!");
    }
  } else {
    // เชื่อมต่อ WiFi หลัก (Client mode)
    Serial.println("\n=== Connecting to WiFi ===");
    Serial.print("SSID: ");
    Serial.println(wifi_ssid);
    
    WiFi.begin(wifi_ssid, wifi_password);
    Serial.print("Connecting to WiFi");
    
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
      delay(1000);
      Serial.print(".");
      attempts++;
    }
    Serial.println();
    
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("✅ WiFi connected successfully!");
      Serial.print("IP address: ");
      Serial.println(WiFi.localIP());
      Serial.print("MAC address: ");
      Serial.println(WiFi.macAddress());
      Serial.print("Signal strength (RSSI): ");
      Serial.print(WiFi.RSSI());
      Serial.println(" dBm");
      Serial.println("\n📱 Connect your phone to the same WiFi:");
      Serial.print("   SSID: ");
      Serial.println(wifi_ssid);
      Serial.print("   Then access: http://");
      Serial.println(WiFi.localIP());
      Serial.println("✅ Internet connection available - Firebase will work!");
      // เพิ่ม mDNS
      if (MDNS.begin("esp32")) {
      Serial.println("✅ mDNS started - Access at: http://esp32.local");
      } else {
       Serial.println("❌ mDNS failed");
    }
    } else {
      Serial.println("❌ Failed to connect to WiFi!");
      Serial.println("Falling back to AP mode...");
      
      // Fallback to AP mode if WiFi connection fails
      if (!WiFi.softAPConfig(local_IP, gateway, subnet)) {
        Serial.println("Failed to configure AP IP address");
      }
      WiFi.softAP(ap_ssid, ap_password);
      Serial.println("✅ WiFi Hotspot created as fallback");
      Serial.print("IP address: ");
      Serial.println(WiFi.softAPIP());
    }
  }
  
  // ตั้งค่า HTTP Server routes
  setupHttpRoutes();
  
  server.begin();
  Serial.println("HTTP Server started");
  Serial.println("Available endpoints:");
  Serial.println("  GET  /buzz?id=<number>  - เรียกโต๊ะ (สำหรับ Flutter app)");
  Serial.println("  GET  /status           - ตรวจสอบสถานะ");
  Serial.println("  GET  /test             - ทดสอบรีเลย์");
  Serial.println("\nSerial Commands:");
  Serial.println("- 0..9  = กดเลข");
  Serial.println("- C     = CALL");
  Serial.println("- B     = Backspace");
  Serial.println("- T<num>= กดเลขทั้งชุดแล้ว CALL (เช่น T16)");
  Serial.println("- P350  = ตั้ง PRESS_DURATION=350 ms");
  Serial.println("- D500  = ตั้ง DELAY_BETWEEN=500 ms");
  Serial.println("- S     = ทดสอบรีเลย์ทั้งหมด");
  Serial.println("- H     = แสดงคำสั่งทั้งหมด\n");
}

void setupHttpRoutes() {
  // หน้าแรก
  server.on("/", []() {
    String html = "<!DOCTYPE html><html><head><title>ESP32 Table System</title></head><body>";
    html += "<h1>ESP32 Table System</h1>";
    html += "<p>Status: <strong>Online</strong></p>";
    html += "<p>IP: " + (USE_AP_MODE ? WiFi.softAPIP().toString() : WiFi.localIP().toString()) + "</p>";
    html += "<p>Relay Type: 5V 4CH x 3 units (12 channels)</p>";
    html += "<p>Active Low: " + String(ACTIVE_LOW ? "true" : "false") + "</p>";
    html += "<h2>Test Commands:</h2>";
    html += "<p><a href='/buzz?id=1'>Test Table 1</a></p>";
    html += "<p><a href='/buzz?id=5'>Test Table 5</a></p>";
    html += "<p><a href='/buzz?id=12'>Test Table 12</a></p>";
    html += "<p><a href='/test'>Test All Relays</a></p>";
    html += "<h2>Status:</h2>";
    html += "<p><a href='/status'>Check Status</a></p>";
    html += "</body></html>";
    server.send(200, "text/html", html);
  });
  
  // เรียกโต๊ะ (สำหรับ Flutter app)
  server.on("/buzz", HTTP_GET, handleBuzz);
  server.on("/buzz", HTTP_OPTIONS, handleBuzz);
  
  // ตรวจสอบสถานะ
  server.on("/status", HTTP_GET, handleStatus);
  
  // ทดสอบรีเลย์
  server.on("/test", HTTP_GET, handleTest);
  
  // CORS headers
  server.onNotFound([]() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    server.sendHeader("Access-Control-Max-Age", "86400");
    server.send(404, "text/plain", "Not Found");
  });
}

void handleBuzz() {
  // เพิ่ม CORS headers
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  server.sendHeader("Access-Control-Max-Age", "86400");
  
  // จัดการ OPTIONS request (preflight)
  if (server.method() == HTTP_OPTIONS) {
    server.send(200, "text/plain", "");
    return;
  }
  
  String queueNumber = server.arg("id");
  Serial.println("HTTP: Received buzz request for table: " + queueNumber);
  
  if (queueNumber.length() == 0) {
    server.send(400, "text/plain", "Missing id parameter");
    return;
  }
  
  int tableNum = queueNumber.toInt();
  if (tableNum < 1 || tableNum > 99) {
    server.send(400, "text/plain", "Invalid table number (1-99)");
    return;
  }
  
  // เรียกใช้ฟังก์ชัน callNumber()
  callNumber(tableNum);
  
  // ส่ง response กลับ
  String response = "{";
  response += "\"success\":true,";
  response += "\"table\":" + String(tableNum) + ",";
  response += "\"message\":\"Table " + String(tableNum) + " called\"";
  response += "}";
  server.send(200, "application/json", response);
}

void handleStatus() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  String response = "{";
  response += "\"status\":\"online\",";
  response += "\"ip\":\"" + (USE_AP_MODE ? WiFi.softAPIP().toString() : WiFi.localIP().toString()) + "\",";
  response += "\"wifi\":\"" + String(USE_AP_MODE ? ap_ssid : wifi_ssid) + "\",";
  response += "\"signal\":" + String(WiFi.RSSI()) + ",";
  response += "\"relay_type\":\"5V 4CH x 3 units (12 channels)\",";
  response += "\"active_low\":" + String(ACTIVE_LOW ? "true" : "false") + ",";
  response += "\"press_duration\":" + String(PRESS_DURATION) + ",";
  response += "\"delay_between\":" + String(DELAY_BETWEEN);
  response += "}";
  
  server.send(200, "application/json", response);
}

void handleTest() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  
  Serial.println("HTTP: Testing all relays...");
  testAllRelays();
  
  String response = "{";
  response += "\"success\":true,";
  response += "\"message\":\"All relays tested\"";
  response += "}";
  server.send(200, "application/json", response);
}

void loop() {
  // จัดการ HTTP requests
  server.handleClient();
  
  // จัดการ Serial commands
  handleSerial();
  
  // ตรวจสอบ Firestore สำหรับคำสั่งใหม่ (ทุก 3 วินาที)
  if (enableFirestore && millis() - lastFirestoreCheck >= firestoreCheckInterval) {
    lastFirestoreCheck = millis();
    checkFirestoreCommands();
  }
}

// ========== ฟังก์ชันหลัก ==========

void pressPin(int pin) {
  int press   = ACTIVE_LOW ? LOW  : HIGH;
  int release = ACTIVE_LOW ? HIGH : LOW;
  
  digitalWrite(pin, press);
  delay(PRESS_DURATION);
  digitalWrite(pin, release);
}

void pressDigit(int d) {
  if (d < 0 || d > 9) return;
  pressPin(DIGIT_PINS[d]);
  Serial.print("[OK] Digit "); Serial.print(d); Serial.println(" pressed");
}

void pressCall() {
  if (PIN_CALL < 0) return;
  pressPin(PIN_CALL);
  Serial.println("[OK] CALL pressed");
}

void pressBackspace() {
  if (PIN_BACKSPACE < 0) return;
  pressPin(PIN_BACKSPACE);
  Serial.println("[OK] BACKSPACE pressed");
}

void callNumber(int number) {
  String s = String(number);
  Serial.println("[CALL] Calling table " + s);
  
  for (int i = 0; i < s.length(); i++) {
    pressDigit(s[i] - '0');
    delay(DELAY_BETWEEN);
  }
  delay(DELAY_BETWEEN * 2);
  pressCall();
  Serial.println("[OK] Table " + s + " call sequence completed");
}

void testAllRelays() {
  Serial.println("[TEST] Testing all relays...");
  
  // ทดสอบเลข 0-9
  for (int i = 0; i < 10; i++) {
    Serial.print("[TEST] Testing digit "); Serial.println(i);
    pressDigit(i);
    delay(1000); // เพิ่มเวลาหน่วง
  }
  
  // ทดสอบ CALL
  Serial.println("[TEST] Testing CALL");
  pressCall();
  delay(1000);
  
  // ทดสอบ Backspace
  Serial.println("[TEST] Testing Backspace");
  pressBackspace();
  delay(1000);
  
  Serial.println("[TEST] All relays tested");
}

void testSingleRelay(int pin) {
  Serial.print("[TEST] Testing GPIO "); Serial.println(pin);
  
  // ส่งสัญญาณ HIGH
  digitalWrite(pin, HIGH);
  Serial.println("  - Sending HIGH signal");
  delay(1000);
  
  // ส่งสัญญาณ LOW
  digitalWrite(pin, LOW);
  Serial.println("  - Sending LOW signal");
  delay(1000);
}

void handleSerial() {
  if (!Serial.available()) return;
  String input = Serial.readStringUntil('\n');
  input.trim();
  if (input.length() == 0) return;

  char cmd = input.charAt(0);
  switch (cmd) {
    case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9':
      pressDigit(cmd - '0');
      break;
    case 'C': case 'c':
      pressCall();
      break;
    case 'B': case 'b':
      pressBackspace();
      break;
    case 'T': case 't':
      if (input.length() > 1) callNumber(input.substring(1).toInt());
      break;
    case 'P': case 'p':
      if (input.length() > 1) { 
        PRESS_DURATION = input.substring(1).toInt(); 
        Serial.print("[SET] PRESS_DURATION="); Serial.println(PRESS_DURATION); 
      }
      break;
    case 'D': case 'd':
      if (input.length() > 1) { 
        DELAY_BETWEEN = input.substring(1).toInt(); 
        Serial.print("[SET] DELAY_BETWEEN="); Serial.println(DELAY_BETWEEN); 
      }
      break;
    case 'S': case 's':
      testAllRelays();
      break;
    case 'G': case 'g':
      if (input.length() > 1) {
        int pin = input.substring(1).toInt();
        testSingleRelay(pin);
      } else {
        Serial.println("Usage: G<pin> (e.g., G33)");
      }
      break;
    case 'H': case 'h':
      Serial.println("\n=== Available Commands ===");
      Serial.println("0-9: Press digit");
      Serial.println("C: Press CALL");
      Serial.println("B: Press Backspace");
      Serial.println("T<num>: Call table number (e.g., T16)");
      Serial.println("P<ms>: Set press duration (e.g., P350)");
      Serial.println("D<ms>: Set delay between (e.g., D500)");
      Serial.println("S: Test all relays");
      Serial.println("G<pin>: Test single GPIO pin (e.g., G33)");
      Serial.println("H: Show this help");
      break;
    default:
      Serial.println("Unknown command. Type 'H' for help.");
      break;
  }
}

// ========== Firestore Functions ==========

// ตรวจสอบคำสั่งใหม่จาก Firestore
void checkFirestoreCommands() {
  if (strlen(firebaseProjectId) == 0) {
    // ยังไม่ได้ตั้งค่า Firebase
    Serial.println("[Firestore] Firebase Project ID not configured");
    return;
  }
  
  HTTPClient http;
  // ใช้ Firestore REST API (ต้องใช้ API key สำหรับ authentication)
  String url = "https://firestore.googleapis.com/v1/projects/" + String(firebaseProjectId) + 
               "/databases/(default)/documents/esp32_commands?pageSize=10";
  
  // เพิ่ม API key ใน URL
  if (strlen(firebaseApiKey) > 0) {
    url += "&key=" + String(firebaseApiKey);
  }
  
  Serial.println("[Firestore] Checking for new commands...");
  Serial.println("[Firestore] URL: " + url);
  
  http.begin(url);
  http.setTimeout(10000);  // เพิ่ม timeout เป็น 10 วินาที
  http.addHeader("Content-Type", "application/json");
  
  int httpCode = http.GET();
  
  Serial.println("[Firestore] HTTP Response Code: " + String(httpCode));
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    Serial.println("[Firestore] Received data length: " + String(payload.length()));
    
    // Parse JSON
    DynamicJsonDocument doc(4096);
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error && doc.containsKey("documents")) {
      JsonArray documents = doc["documents"].as<JsonArray>();
      
      // วนลูปหาคำสั่งใหม่ (เรียงจากใหม่ไปเก่า)
      for (JsonObject docObj : documents) {
        if (!docObj.containsKey("name")) continue;
        
        // ดึง document ID จาก path
        String fullPath = docObj["name"].as<String>();
        int lastSlash = fullPath.lastIndexOf('/');
        String commandId = fullPath.substring(lastSlash + 1);
        
        // ข้ามคำสั่งที่ประมวลผลแล้ว
        if (commandId == lastProcessedCommandId) {
          continue;
        }
        
        // ดึงข้อมูล fields
        if (!docObj.containsKey("fields")) continue;
        JsonObject fields = docObj["fields"].as<JsonObject>();
        
        String status = "pending";
        String cmd = "";
        int tableNumber = 0;
        
        if (fields.containsKey("status") && fields["status"].containsKey("stringValue")) {
          status = fields["status"]["stringValue"].as<String>();
        }
        if (fields.containsKey("command") && fields["command"].containsKey("stringValue")) {
          cmd = fields["command"]["stringValue"].as<String>();
        }
        if (fields.containsKey("tableNumber") && fields["tableNumber"].containsKey("integerValue")) {
          tableNumber = fields["tableNumber"]["integerValue"].as<int>();
        }
        
        // ตรวจสอบว่าคำสั่งยัง pending และเป็นคำสั่ง buzz
        if (status == "pending" && cmd == "buzz" && tableNumber > 0) {
          Serial.println("[Firestore] Found new command: " + commandId + " - Call table " + String(tableNumber));
          
          // เรียก HTTP endpoint ไปที่ตัวเอง
          callNumber(tableNumber);
          
          // อัปเดตสถานะคำสั่งเป็น completed
          updateCommandStatus(commandId, "completed");
          
          // บันทึก ID ของคำสั่งที่ประมวลผลแล้ว
          lastProcessedCommandId = commandId;
          
          break; // ประมวลผลทีละคำสั่ง
        }
      }
    } else {
      Serial.println("[Firestore] JSON parse error: " + String(error.c_str()));
    }
  } else {
    String errorPayload = http.getString();
    Serial.println("[Firestore] HTTP error: " + String(httpCode));
    Serial.println("[Firestore] Error response: " + errorPayload);
    
    if (httpCode == HTTP_CODE_UNAUTHORIZED || httpCode == 403) {
      Serial.println("[Firestore] ⚠️ Authentication failed!");
      Serial.println("[Firestore] Possible solutions:");
      Serial.println("[Firestore] 1. Check Firestore Security Rules allow public access");
      Serial.println("[Firestore] 2. Verify API key is correct");
      Serial.println("[Firestore] 3. Set enableFirestore = false to disable Firestore check");
    } else if (httpCode == -1) {
      Serial.println("[Firestore] ⚠️ Connection failed - check WiFi connection");
    } else if (httpCode == 404) {
      Serial.println("[Firestore] ⚠️ Collection not found - esp32_commands may not exist yet");
    } else {
      Serial.println("[Firestore] ⚠️ Unknown error - HTTP code: " + String(httpCode));
    }
  }
  
  http.end();
}

// อัปเดตสถานะคำสั่งใน Firestore
void updateCommandStatus(String commandId, String status) {
  HTTPClient http;
  // ใช้ Firestore REST API PATCH
  String url = "https://firestore.googleapis.com/v1/projects/" + String(firebaseProjectId) + 
               "/databases/(default)/documents/esp32_commands/" + commandId + "?updateMask.fieldPaths=status";
  
  // เพิ่ม API key ใน URL
  if (strlen(firebaseApiKey) > 0) {
    url += "&key=" + String(firebaseApiKey);
  }
  
  http.begin(url);
  http.setTimeout(10000);  // เพิ่ม timeout เป็น 10 วินาที
  http.addHeader("Content-Type", "application/json");
  
  // สร้าง Firestore document format
  String jsonData = "{\"fields\":{\"status\":{\"stringValue\":\"" + status + "\"}}}";
  
  int httpCode = http.PATCH(jsonData);
  
  if (httpCode == HTTP_CODE_OK) {
    Serial.println("[Firestore] ✅ Updated command status: " + commandId + " -> " + status);
  } else {
    String errorPayload = http.getString();
    Serial.println("[Firestore] ❌ Failed to update status. HTTP: " + String(httpCode));
    Serial.println("[Firestore] Error response: " + errorPayload);
  }
  
  http.end();
}
