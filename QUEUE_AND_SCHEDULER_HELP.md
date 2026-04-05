# Stellar Download Manager - Queue & Scheduler Help

## Table of Contents
- [Overview](#overview)
- [Opening the Scheduler](#opening-the-scheduler)
- [Queue Types](#queue-types)
- [Default Queues](#default-queues)
- [The Scheduler Dialog](#the-scheduler-dialog)
- [Schedule Tab](#schedule-tab)
- [Files in Queue Tab](#files-in-queue-tab)
- [Download Limits Tab](#download-limits-tab)
- [Starting and Stopping Queues](#starting-and-stopping-queues)
- [Moving Downloads Between Queues](#moving-downloads-between-queues)
- [Creating Custom Queues](#creating-custom-queues)
- [Saving Changes](#saving-changes)

---

## Overview

The Queue and Scheduler system in Stellar Download Manager allows you to organize, prioritize, and automate your downloads. You can create multiple download queues, schedule when they start and stop, set download limits, and define post-completion actions.

---

## Opening the Scheduler

The Scheduler dialog can be opened in three ways:

1. **Click the "Scheduler" button** on the toolbar
2. **Select "Options → Scheduler"** from the main menu
3. **Select "Downloads → Scheduler"** from the main menu

---

## Queue Types

Stellar Download Manager supports two types of queues:

### Download Queue (One-time Downloading)
- **Purpose**: Download files once and remove them when complete
- **Behavior**: Files are deleted from the queue when successfully downloaded
- **Use Case**: Regular file downloads, bulk downloads
- **Schedule Options**: Start once at a specific time, or daily at specific times on selected days

### Synchronization Queue (Periodic Synchronization)
- **Purpose**: Repeatedly check and download updated files from the same source
- **Behavior**: Files remain in the queue after being downloaded, allowing periodic re-syncing
- **Use Case**: Syncing folders, keeping local copies updated, monitoring for changes
- **Schedule Options**: Start at a time, then repeat every X hours and Y minutes on selected days

---

## Default Queues

Stellar Download Manager includes three default queues:

1. **Main download queue** - The default queue for new downloads (One-time downloading)
2. **Synchronization queue** - For periodic file synchronization (Periodic synchronization)
3. **Download limits** - Special queue for testing and configuring bandwidth quotas

---

## The Scheduler Dialog

The Scheduler dialog displays:

### Left Sidebar
- **Queue List**: Shows all available queues
  - Click a queue name to select it and view its settings
  - Current selection is highlighted in blue
- **New queue**: Button to create custom download queues
- **Delete**: Remove a selected custom queue (cannot delete default queues)

### Center Pane
Displays the selected queue name at the top

### Tabs (for Download and Synchronization Queues)
- **Schedule Tab** - Configure when the queue runs
- **Files in the queue Tab** - View and reorder files, set concurrent downloads

### Download Limits Queue
When selected, hides the tabs and displays only the Download Limits section

### Bottom Buttons
- **Start now**: Immediately start processing the selected queue
- **Stop**: Stop the currently running queue
- **Apply**: Save all changes and stay on the current queue
- **Close**: Save changes and close the dialog

---

## Schedule Tab

### Queue Type Selection
Choose the type of queue at the top:

**One-time downloading** (Download Queue)
- Downloads complete once and are removed from queue

**Periodic synchronization** (Synchronization Queue)
- Downloads are kept in queue for periodic re-syncing

### Start on Stellar Startup
- **Checkbox**: Enable to automatically start this queue when Stellar launches

### Start Time Configuration

#### Enable Scheduled Start
- **Checkbox**: "Start download at" - Enable to schedule when the queue begins

#### Schedule Type
- **Once at**: Start the queue one time at the specified time (Download queues only)
- **Daily**: Start the queue every day at the specified time (Download queues only)

#### Days Selection (Download Queues)
When **Daily** is selected, choose which days to start:
- Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday

#### Periodic Restart (Synchronization Queues)
For synchronization queues, instead of daily scheduling:
- **Start again every**: Configure repeat interval
  - Set hours (0-23)
  - Set minutes (0-59)
- **Select Days**: Choose which days the periodic restart applies

### Stop Time Configuration
- **Checkbox**: "Stop download at" - Enable to automatically stop queue processing
- **Time**: Specify when to stop (independent of start time)
- The queue will stop even if "Start download at" is not enabled

### Retry Configuration
- **Checkbox**: "Number of retries for each file if downloading failed"
- **Value**: Set the maximum number of retry attempts (1-100)
- Without this, failed files retry indefinitely every 30 seconds

### Post-Completion Actions
These actions trigger when the queue finishes processing (not if manually stopped):

- **Exit Stellar when done**: Close the application after queue completion
- **Turn off computer when done**: Shut down the system
  - **Force processes to terminate**: Forcefully close all applications (use with caution - may cause data loss)
- **Open the following file when done**: Execute a program or batch file
  - Click "..." to browse for a file
  - Use a .BAT file to run multiple commands

---

## Files in Queue Tab

### Concurrent Downloads Setting
- **Label**: "Download X files at the same time"
- **Range**: 1-10 files
- **Note**: Sites that don't allow multiple connections should be set to 1

### File Table
- **Columns**: File Name, Size, Status, Time Left
- **Display**: Shows all files in the current queue

### File Order Control
- **Move Up (↑)**: Move selected file up in the queue
- **Move Down (↓)**: Move selected file down in the queue
- **Delete**: Remove file from queue

**Note**: This tab is only available for Download and Synchronization queues, not for Download limits.

---

## Download Limits Tab

### Purpose
Set bandwidth quotas and download limits for fair usage policies on metered connections.

### Enable Download Limits
- **Checkbox**: "Download limits" - Enable bandwidth throttling

### Quota Configuration
- **Download no more than**: Specify the data amount (1-100000 MBytes)
- **every**: Time period (1-24 hours)
- **Example**: "Download no more than 200 MBytes every 5 hours"

### Behavior
- When the quota is reached, downloads pause
- Downloads automatically resume when the time period resets
- This allows downloading at maximum speed while staying within fair usage limits

### Warning Option
- **Checkbox**: "Show warning before stopping downloads"
- When enabled, shows a notification when approaching the bandwidth limit

**Note**: Download limits are only configurable in the Download limits queue. This is a special queue accessible from the queue list in the Scheduler dialog.

---

## Starting and Stopping Queues

### Method 1: Scheduler Dialog
- Select the queue in the Scheduler
- Click **Start now** to begin processing
- Click **Stop** to pause the queue

### Method 2: Toolbar Dropdowns
- **Start Queue dropdown**: Shows all available queues
- **Stop Queue dropdown**: Shows all running queues
- Select a queue to start or stop it
- These dropdowns automatically update when queues are created/deleted

### Method 3: Main Menu
- **Downloads → Start Queue → [Queue Name]**
- **Downloads → Stop Queue → [Queue Name]**
- Submenus dynamically list all available queues

### Method 4: Download Table Context Menu
- Right-click a download in the table
- Select **Resume** to start processing immediately
- Select **Stop** to pause processing

---

## Moving Downloads Between Queues

### Via Download Table Context Menu
1. Right-click on a download
2. Select **Move to Queue**
3. Choose from the submenu:
   - **Synchronization queue**
   - **[Any custom queue]**
4. Download moves to the selected queue

### Via Drag and Drop
1. Select a download in the main table
2. Drag it to a queue in the sidebar
3. Drop to assign it to that queue

---

## Creating Custom Queues

### Creating a New Queue
1. Open the Scheduler dialog
2. Click **New queue** button
3. Enter a name in the dialog box
4. Click **OK**
5. The new queue appears in the queue list

### Queue Defaults
- New queues are created as **Download queues** by default
- Change to **Periodic synchronization** in the Schedule tab if needed
- All settings can be customized per queue

### Deleting Custom Queues
1. Select the queue in the left list
2. Click **Delete** button
3. Queue is removed (cannot delete default queues)

**Note**: Ensure the queue is empty before deleting, or move downloads to another queue first.

---

## Saving Changes

### Automatic Saving
- Moving files between queues is saved immediately
- Changes are automatically saved when:
  - You switch to a different queue
  - You close the Scheduler dialog

### Manual Saving
- Click **Apply** to explicitly save all changes
- Use Apply when you want to save settings without leaving the current queue

### Settings That Save
All of the following settings persist to disk:
- Queue names and types
- Schedule configurations (start/stop times, days)
- Retry settings
- Post-completion actions
- Download limits quotas
- Concurrent download count per queue

---

## Tips & Best Practices

### For Slow/Unreliable Connections
1. Create a queue with retries enabled (5-10 attempts)
2. Set concurrent downloads to 1
3. Enable "Stop download at" to avoid excessive retries

### For Bandwidth Management
1. Use the **Download limits** queue to set quotas
2. Configure limits based on your ISP's fair usage policy
3. Enable "Show warning before stopping downloads"

### For Large Batch Downloads
1. Create a custom queue for the batch
2. Set appropriate concurrency (3-5 files recommended)
3. Schedule with "Stop download at" to avoid overnight bandwidth usage

### For File Synchronization
1. Use a **Synchronization queue**
2. Enable "Start again every" with appropriate intervals
3. Select the days you want synchronization to occur
4. Monitor the queue in the main window

### For Automated Downloads
1. Schedule the queue to start at off-peak hours
2. Enable post-completion action to close app or shutdown
3. Use Download limits if on a metered connection
4. Test with a small queue first before running large batches

---

## Troubleshooting

### Queue Won't Start
- Verify it's not already running in the Stop Queue dropdown
- Check that the start time is set correctly
- Ensure files exist in the queue

### Downloads Not Progressing
- Check concurrent download setting (set to 1-3 for problem sites)
- Verify "Stop download at" time hasn't been reached
- Review download limits if enabled

### Files Not Downloading in Order
- Use the up/down arrow buttons to reorder files
- Set concurrent downloads to 1 if order is critical

### Custom Queue Won't Delete
- Ensure all downloads are moved to another queue first
- Delete cannot be used on default queues

---

## Related Features

- **Speed Limiter**: Set global bandwidth limits in Options → Speed Limiter
- **Categories**: Organize downloads by type in the sidebar
- **Download Progress Dialog**: View detailed progress for individual downloads
- **Browser Integration**: Intercept downloads from Firefox/Chrome extensions

---

*For more information, visit the Stellar Download Manager documentation or check the Help menu.*
