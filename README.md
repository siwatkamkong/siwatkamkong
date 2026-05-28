# 🍽️ Smart Restaurant Queue Calling System (IoT + Mobile Application)

## 📌 Overview

This project is a **Smart Restaurant Queue Calling System** developed to improve queue management and reduce operational workload inside restaurants.

Customers can scan a QR Code to access the food ordering application, place orders, and receive queue notifications automatically through wireless pager devices.

The system integrates a **Flutter Mobile Application**, **Firebase Cloud Database**, and **ESP32 Microcontroller** to automate queue calling without requiring staff to manually press pager buttons.

---

## 🎯 Problem Statement

In many restaurants and cafés, queue management is still handled manually by employees, causing several operational problems such as:

- Long customer waiting times
- Human errors in queue calling
- High dependency on staff
- Increased labor costs
- Slow customer service during peak hours

Therefore, this project was developed to automate the queue calling process using IoT technology and mobile applications.

---

## 🚀 Key Features

### 👨‍🍳 Customer Features
- Scan QR Code to access ordering system
- Order food directly from mobile application
- Real-time queue monitoring
- Faster and more convenient ordering experience

### 🛠️ Admin Features
- Queue management dashboard
- Real-time order monitoring
- Automatic queue calling system
- Queue history management
- Pager control through application

### 🤖 IoT Features
- ESP32 receives queue data from Firebase
- Relay modules automatically trigger pager buttons
- Wireless pager notification system
- Real-time communication between app and hardware

---

## 🔄 System Flow

```text
+------------------------------------------------------+
|      SMART RESTAURANT QUEUE CALLING SYSTEM           |
+------------------------------------------------------+
                         |
                         v
              +----------------------+
              | Customer Scans QR    |
              | Code from Restaurant |
              +----------------------+
                         |
                         v
              +----------------------+
              |  Mobile Application  |
              |   (Flutter App)      |
              +----------------------+
                         |
                         v
              +----------------------+
              |   Customer Orders    |
              |      Food Menu       |
              +----------------------+
                         |
                         v
              +----------------------+
              | Firebase Firestore   |
              | Realtime Database    |
              +----------------------+
                         |
                         v
              +----------------------+
              |   Admin Dashboard    |
              |  Queue Management    |
              +----------------------+
                         |
                         v
              +----------------------+
              | ESP32 Receives Data  |
              | from Firebase Cloud  |
              +----------------------+
                         |
                         v
              +----------------------+
              | Relay Module Trigger |
              | Pager Button Press   |
              +----------------------+
                         |
                         v
              +----------------------+
              | Customer Pager Alert |
              | Queue Notification   |
              +----------------------+
```

### 🛠️ Hardware Used
ESP32
Relay Module 4CH x3
Restaurant Pager Device
7-Segment Display
433 MHz Wireless System
Power Supply Unit

### 💻 Software & Technology
Mobile Application
Flutter
Dart
Backend & Cloud
Firebase Firestore
Firebase Realtime Database
REST API
Embedded System
ESP32
Arduino IDE
IoT System Design

### 🔍 How It Works

Customers scan a QR Code provided by the restaurant to access the food ordering application. Orders and queue information are stored in Firebase Cloud Database in real-time.

The admin dashboard allows restaurant staff to manage orders and call customer queues directly from the application.

When a queue is called, the ESP32 receives data from Firebase and automatically controls relay modules that physically trigger the restaurant pager device buttons. Customers are then notified through their wireless pagers without requiring staff to manually press the pager system.

The entire workflow is integrated into a single automated platform.

### 📊 Project Objectives
Reduce restaurant labor costs
Improve queue management efficiency
Reduce customer waiting problems
Automate pager calling system
Improve customer service experience
Integrate IoT with restaurant operations

### 🧩 System Scope
QR Code ordering system
Android & iOS mobile support
Real-time queue monitoring
Queue data storage
Sales and order tracking
IoT-based pager automation
Easy-to-use UI/UX design

## 👨‍💻 Developer

* Siwat Kamkong (Computer Engineering)
* Interested in Web Development, Mobile Applications, and System Development. 

## 🏢 Organization
National Telecom Public Company Limited (NT)
Hat Yai Branch, Thailand

## 📄 License
This project was developed for educational and organizational internship purposes.
