# Firefox from RAM Disk

![app logo](./Firefox%20Ramdisk/fframdisk.png)

## Motivation

Firefox is known for generating significant data writes, even with disk caching turned off.
This lightweight app reduces SSD wear by running the Firefox profile from a RAM disk.

## How it works

1. Auto detects default Firefox profile and its folder size.
2. Creates RAM disk sized accordingly.
3. Copies Firefox profile files to RAM disk using `rsync`.
5. Launches Firefox with the RAM disk profile.
6. Waits for Firefox termination
7. Sync changes from ramdisk back to disk

## Requirements

- macOS
- Firefox installed in `/Applications/Firefox.app`
- Swift & Cocoa framework

## Usage

Build and run the app from Xcode.

## TODO

Auto Disable disk caching - firefox settings 

## License

MIT License
