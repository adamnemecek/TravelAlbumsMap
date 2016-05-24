//
//  ItemsInDirectoryLoader.swift
//  The Photo Map
//
//  Created by Christian Dunn on 5/14/16.
//  Copyright © 2016 Christian Dunn. All rights reserved.
//

import Foundation
import AppKit

public class ItemsInDirectoryLoader {
    
    var VC : ViewController;
    var DLWC : DirectoryLoaderWindowController? = nil;
    var openPanel : NSOpenPanel;
    
    init(withViewController viewController : ViewController) {
        
        VC = viewController;
        openPanel = NSOpenPanel();
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["photoslibrary"]
    }
    
    public func loadItemsFromDirectory() {
        
        openPanel.canChooseDirectories = true
        getPath();
    }
    
    public func loadPhotoLibrary() {
        
        getPath();
    }
    
    private func getPath() {
        
        let window = NSApplication.sharedApplication().mainWindow;
        openPanel.beginSheetModalForWindow(window!, completionHandler: { (result) -> Void in
            if result == NSFileHandlingPanelOKButton {
                self._loadItemsFromDirectory(withPath: self.openPanel.URL!);
            }
        });
    }
    
    private func _loadItemsFromDirectory(withPath path: NSURL) {
        
        let fileEnumerator : FileEnumerator = FileEnumerator.init(withPath: path);
        
        let storyboard : NSStoryboard = NSStoryboard.init(name: "Main", bundle: nil);
        DLWC = storyboard.instantiateControllerWithIdentifier("DateFilterWindowController") as? DirectoryLoaderWindowController;
        DLWC?.showWindow(nil);
        fileEnumerator.getAllImageFiles(VC, dlwc: DLWC!);
    }
}
