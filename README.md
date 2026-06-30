# FDS & SMV Guided GUI

GUI-assisted preprocessor for [FDS](https://github.com/firemodels/fds) and Smokeview. The goal is to help users transform building drawings into structured fire simulation inputs, review the extracted building geometry, define prevention systems and incident scenarios, and export runnable `.fds` cases for simulation and visualization.

## Project Vision

This project is not a replacement for FDS or Smokeview. It is a guided interface built on top of them.

The intended workflow is:

1. Import a building drawing, floor plan, or existing FDS draft.
2. Extract and review solid building geometry such as walls, rooms, openings, obstructions, and vents.
3. Identify and confirm fire prevention elements such as extinguishers, hydrants, exits, and signage.
4. Guide the user through required fire scenario inputs:
   - fuel/material to burn;
   - explanation of each fuel option;
   - incident location;
   - burn coefficient or HRRPUA;
   - simulation duration;
   - mesh resolution;
   - ventilation assumptions.
5. Generate a valid FDS input file.
6. Run FDS locally.
7. Open the generated results in Smokeview.

## Current Status

This repository currently contains an early local GUI prototype.

Implemented so far:

- responsive HTML/CSS/JavaScript interface;
- guided workflow screens for drawing, building geometry, prevention systems, fire scenario, and FDS export;
- dropdown-driven fuel selection with explanatory text;
- output-folder selection for generated FDS cases;
- local PowerShell backend;
- detection of local FDS and Smokeview executables;
- ability to call FDS with a configured `.fds` file;
- ability to open a generated `.smv` file in Smokeview.

Still planned:

- PDF/DWG/DXF/image drawing import;
- OCR and computer vision pipeline for plan interpretation;
- editable extracted geometry model;
- prevention-symbol recognition;
- FDS file generation from reviewed geometry;
- validation rules for mandatory FDS inputs;
- richer Smokeview/result inspection from the GUI.

## Local Requirements

This prototype is designed for Windows.

Required:

- FDS installed locally;
- Smokeview installed locally;
- PowerShell;
- a modern browser.

The current default paths are:

```text
C:\Program Files\firemodels\FDS6\bin\fds.exe
C:\Program Files\firemodels\SMV6\smokeview.exe
```

## Running The Prototype

From the project folder, run:

```powershell
.\start-gui.ps1
```

Or double-click:

```text
start-gui.bat
```

Then open:

```text
http://127.0.0.1:8765
```

## Architecture

```text
Building drawing / FDS draft
        |
        v
GUI-assisted extraction and review
        |
        v
Building geometry + prevention systems + fire scenario inputs
        |
        v
Generated FDS input file
        |
        v
FDS simulation
        |
        v
Smokeview visualization
```

## Repository Structure

```text
index.html       Main GUI layout
styles.css       Visual design and responsive layout
app.js           Browser-side interaction logic
start-gui.ps1    Local PowerShell backend for FDS/Smokeview integration
start-gui.bat    Windows launcher for the local GUI
```

## Notes

FDS and Smokeview are developed by NIST and the firemodels project. This GUI is intended as a higher-level modeling assistant that generates and executes compatible FDS cases.

Official resources:

- [FDS/Smokeview manuals](https://pages.nist.gov/fds-smv/manuals.html)
- [firemodels/fds repository](https://github.com/firemodels/fds)
"# FDS_SMV_GUI_PORTUGUESE" 
