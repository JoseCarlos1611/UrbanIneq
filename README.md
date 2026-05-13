# 🗺️ Unfair Urban Dataset

**Geospatial analysis of urban inequalities in Andalusia**

An open-source, end-to-end system that automates the download, processing, and visualization of spatial data for the analysis of urban injustice and inequality in Andalusian municipalities. It combines advanced geospatial analysis techniques with a modern, interactive web interface.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Main Features](#main-features)
- [System Architecture](#system-architecture)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Usage](#usage)
- [Data Sources](#data-sources)
- [Technology Stack](#technology-stack)
- [Detailed Components](#detailed-components)
- [APIs and Endpoints](#apis-and-endpoints)
- [Development](#development)

---

## 📖 Overview

The **Unfair Urban Dataset** project analyzes and visualizes patterns of inequality in Andalusian cities through:

- **Accessibility analysis**: distances to green areas and public/private healthcare facilities
- **Socioeconomic indicators**: income, unemployment, education, and population density
- **Demographic data**: age, foreign population, and loneliness/single-person households
- **Geospatial visualization**: interactive maps of variables and identified biases

The system automatically identifies **which factors generate the greatest inequality** in each municipality, enabling researchers and policymakers to make data-driven decisions.

---

## ✨ Main Features

✅ **Automated processing** of spatial data from multiple public sources  
✅ **Modern REST API** for on-demand queries and analysis  
✅ **Interactive web interface** with maps, charts, and visualizations  
✅ **Full coverage of Andalusia**, with access to all municipalities  
✅ **Bias analysis** to identify variables with the greatest spatial variation  
✅ **Result downloads** in multiple formats: PNG, RDS, ZIP  
✅ **Accessibility calculations** using the OSRM routing engine  
✅ **Fully containerized** with Docker Compose  

---

## 🏗️ System Architecture

The project is structured as a **4-microservice architecture** orchestrated with Docker Compose:

```text
┌─────────────────────────────────────────────────────────────┐
│                    WEB CLIENT (Frontend)                    │
│              React + TypeScript + Vite + Nginx              │
│                         Port 8081                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP/REST
┌────────────────────▼────────────────────────────────────────┐
│              FastAPI Gateway (Python Backend)               │
│        Job management, municipalities, file downloads        │
│                         Port 8080                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP calls
┌────────────────────▼────────────────────────────────────────┐
│      R Plumber (Geospatial Analysis + Visualizations)       │
│       Complex calculations and spatial data processing       │
│                         Port 8000                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP
┌────────────────────▼────────────────────────────────────────┐
│       OSRM Backend (Open Source Routing Machine)            │
│          Urban route and distance calculations               │
│                         Port 5001                           │
└─────────────────────────────────────────────────────────────┘
