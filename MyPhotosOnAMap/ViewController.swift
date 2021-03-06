//
//  ViewController.swift
//  MyPhotosOnAMap
//
//  Created by Christian Dunn on 4/19/16.
//  Copyright © 2016 Christian Dunn. All rights reserved.
//

import Cocoa
import MapKit
import Foundation
import Quartz

class ViewController: NSViewController, MKMapViewDelegate, NSGestureRecognizerDelegate, HorizontalSizeAdjusterDelegate, RectangularRegionSelectorDelegate {

    var MapView: MKMapView!
    var ProgressBar: NSProgressIndicator!
    var ImageBrowser: IKImageBrowserView!
    var SizeAdjuster : HorizontalSizeAdjuster!
    var MapVsBrowser : Double = 0.5;
    var RegionSelector : RectangularRegionSelector? = nil;
    
    var LatLons : [(CLLocationCoordinate2D, CDMediaObjectWithLocation)] = [];
    var MediaLibraryBackupLatLons : [(CLLocationCoordinate2D, CDMediaObjectWithLocation)] = [];
    var FriendsNeededToNotBeLonely : Int = Constants.MinimumPointsForCluster;
    var ClusterRadius : Double = Constants.ClusterRadius;
    var Clustering : ClusteringAlgorithm<MLMediaObject>? = nil;
    var Timing : NSTimer? = nil;
    var annotations : [ModifiedPinAnnotation] = [];
    var Overlays : [ModifiedClusterAnnotation] = [];
    var ImageBrowserDel : ImageBrowserDelegate? = nil;
    var verticalScroller : NSScroller? = nil;
    var HighlitPoint : MKPointAnnotation? = nil;
    var accessor : MediaLibraryAccessor? = nil;
    var MediaAccessorStatusWindow : DirectoryLoaderWindowController? = nil;
    var YellowPinView : MKPinAnnotationView? = nil;
    var scrollView : NSScrollView!;
    var LastRegionRefreshed : MKCoordinateRegion? = nil;
    var mediaAccessorAlert : NSAlert? = nil;
    
    var BackStack : CDMapRegionStack? = nil;
    var ForwardStack : CDStack<MKCoordinateRegion>? = nil;
    var LastRegion : MKCoordinateRegion? = nil;
    var NavButton : Bool = false;
    
    var DateFilterStart : NSDate;
    var DateFilterFinish : NSDate;
    var DateFilterUse : Bool = false;
    
    static var VC : ViewController?;
    
    static func getMainViewController() -> ViewController? {
        
        return VC;
    }
    
    required init?(coder: NSCoder) {
        
        DateFilterStart = Constants.DateFilterStartDefault;
        DateFilterFinish = Constants.DateFilterFinishDefault;
        super.init(coder: coder);
        initialization();
    }
    
    override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        
        DateFilterStart = Constants.DateFilterStartDefault;
        DateFilterFinish = Constants.DateFilterFinishDefault;
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil);
        initialization();
    }
    
    func initialization() {
        
        ViewController.VC = self;
    }
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        NSApplication.sharedApplication().mainWindow?.backgroundColor = NSColor.whiteColor();        
        Clustering = ClusteringAlgorithm<MLMediaObject>(withMaxDistance: ClusterRadius);
        
        BackStack = CDMapRegionStack.init();
        ForwardStack = CDStack<MKCoordinateRegion>.init();
        let gestureRecognizer = NSPanGestureRecognizer.init(target: self, action: #selector(userTappedMap));
        gestureRecognizer.delegate = self;
        
        ImageBrowser = IKImageBrowserView.init(frame: CGRectMake(0.0, 0.0, 1.0, 1.0));
        ImageBrowser.setIntercellSpacing(CGSizeMake(0.0, 0.0));
        ImageBrowser.setAllowsMultipleSelection(false);
        self.view.addSubview(ImageBrowser);
        ImageBrowserDel = ImageBrowserDelegate.init(imageBrowser: ImageBrowser, delegate: self);
        
        MapView = MKMapView.init(frame: CGRectMake(0.0, 0.0, 1.0, 1.0));
        MapView.mapType = MKMapType.Hybrid;
        MapView.showsScale = true;
        MapView.showsBuildings = true;
        MapView.showsCompass = true;
        MapView.showsZoomControls = true;
        MapView.delegate = self;
        self.view.addSubview(MapView);
        MapView.addGestureRecognizer(gestureRecognizer);
        
        scrollView = NSScrollView.init(frame: ImageBrowser.frame);
        scrollView.documentView = ImageBrowser;
        scrollView.hasVerticalScroller = true;
        self.view.addSubview(scrollView);
        
        ProgressBar = NSProgressIndicator.init(frame: CGRectMake(0.0, 0.0, 100.0, 100.0));
        ProgressBar.style = NSProgressIndicatorStyle.SpinningStyle;
        ProgressBar.indeterminate = true;
        ProgressBar.displayedWhenStopped = true;
        ProgressBar.hidden = true;
        self.view.addSubview(ProgressBar);
        
        SizeAdjuster = HorizontalSizeAdjuster.init(frame: CGRectMake(0.0, 0.0, 1.0, 100.0));
        SizeAdjuster.Delegate = self;
        self.view.addSubview(SizeAdjuster);
        MapVsBrowser = Constants.MapViewFraction;
    }
    
    override func viewDidLayout() {
        
        super.viewDidLayout();
        
        let width = self.view.frame.size.width;
        let height = self.view.frame.size.height;
        
        MapView.setFrameSize(CGSizeMake(CGFloat(Double(width)*MapVsBrowser), height));
        scrollView.setFrameOrigin(CGPointMake(width*CGFloat(MapVsBrowser), 0.0));
        scrollView.setFrameSize(CGSizeMake(width*CGFloat(1-MapVsBrowser), height));
        ProgressBar.setFrameOrigin(CGPointMake(MapView.frame.size.width/2 - 50.0, MapView.frame.size.height/2 - 50.0));
        SizeAdjuster.setFrameSize(CGSizeMake(CGFloat(Constants.SizeAdjusterWidth), height));
        SizeAdjuster.setFrameOrigin(CGPointMake(width*CGFloat(MapVsBrowser)-CGFloat(Constants.SizeAdjusterWidth)/2, 0.0));
        
        if RegionSelector != nil {
            RegionSelector?.frame = MapView.frame;
        }
    }
    
    func loadMapWithFilePaths(mediaObjects: [CDMediaObjectWithLocation]) {
        
        let mediaObjectsWithLocation = mediaObjects.filter {$0.Location != nil};
        LatLons = mediaObjectsWithLocation.map {($0.Location!, $0)};
        refreshPoints();
    }
    
    func loadMapWithLibrary() {
        
        if MediaLibraryBackupLatLons.count == 0 {
            ProgressBar.hidden = false;
            ProgressBar.startAnimation(self);
            if accessor == nil {
                accessor = MediaLibraryAccessor();
            } else {
                accessor?.removeObserverFromMediaLibrary();
            }
            accessor!.setDelegate(self, withSelector: "mediaAccessorDidFinishLoadingAlbums");
            accessor!.setStatusReportSelector("mediaAccessorDidReportStatus");
            
            let storyboard : NSStoryboard = NSStoryboard.init(name: "Main", bundle: nil);
            MediaAccessorStatusWindow = storyboard.instantiateControllerWithIdentifier("DateFilterWindowController") as? DirectoryLoaderWindowController;
            MediaAccessorStatusWindow?.showWindow(nil);
            MediaAccessorStatusWindow?.VC?.setViewController(self);
            
            accessor!.initialize();
        } else {
            LatLons = MediaLibraryBackupLatLons;
            addPoints(LatLons);
        }
    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func mediaAccessorDidReportStatus() {
        
        if accessor == nil {
            return;
        }
        let status = accessor!.StatusMessage;
        MediaAccessorStatusWindow!.VC?.updateLabel(status);
    }
    
    func mediaAccessorDidFinishLoadingAlbums() {
        
        ProgressBar.hidden = true;
        MediaAccessorStatusWindow?.close();
        
        if accessor!.ErrorState {
            accessor?.getMediaObjects().removeAllObjects();
            self.mediaAccessorErrorPrompt();
            return;
        }        
        
        let mediaObjects: Array<MLMediaObject> = accessor!.getMediaObjects() as NSArray as! [MLMediaObject];
        if mediaObjects.count == 0 {
            self.mediaAccessorErrorPrompt();
        }
        
        let attributes = mediaObjects.map {($0.attributes, $0)}.filter {$0.0.indexForKey("latitude") != nil}.filter {$0.0.indexForKey("longitude") != nil};
        let latLons = attributes.map {(CLLocationCoordinate2DMake($0.0["latitude"] as! Double, $0.0["longitude"] as! Double), CDMediaObjectFactory.createFromMlMediaObject(withObject: $0.1))};
        LatLons = latLons;
        MediaLibraryBackupLatLons = LatLons;
        addPoints(LatLons);
    }
    
    func mediaAccessorStop() {
        
        accessor?.reportErrorFindingMedia();
    }
    
    func mediaAccessorErrorPrompt() {
        
        if mediaAccessorAlert == nil {
            
            mediaAccessorAlert = NSAlert.init();
            mediaAccessorAlert!.messageText = (accessor?.getErrorLoadingPhotosMessage())!;
            mediaAccessorAlert!.addButtonWithTitle("Close");
            mediaAccessorAlert!.addButtonWithTitle("Find Photo Library File");
            mediaAccessorAlert!.addButtonWithTitle("Load Folder");
            let response = mediaAccessorAlert!.runModal();
            
            if response == NSAlertSecondButtonReturn {
                let itemLoader : ItemsInDirectoryLoader = ItemsInDirectoryLoader.init(withViewController: self);
                itemLoader.loadPhotoLibrary();
            }
            
            if response == NSAlertThirdButtonReturn {
                let itemLoader : ItemsInDirectoryLoader = ItemsInDirectoryLoader.init(withViewController: self);
                itemLoader.loadItemsFromDirectory();
            }
            
            mediaAccessorAlert = nil;
        }
    }
    
    func userTappedMap(gestureRecognizer : NSGestureRecognizer) {
        
        if gestureRecognizer.state == NSGestureRecognizerState.Ended {
            self.userInitiatedMapChangeDidHappen();
        }
    }
    
    func gestureRecognizer(gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        return true;
    }
    
    func userInitiatedMapChangeDidHappen() {
        
        ForwardStack?.removeAll();
    }
    
    func setTimerForPointsRefresh() {
        
        if Timing != nil {
            Timing?.invalidate();
            Timing = nil;
        }
        Timing = NSTimer.scheduledTimerWithTimeInterval(1.00, target: self, selector: #selector(refreshPoints), userInfo: nil, repeats: false);
    }
    
    func mapView(mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        
        if LastRegion != nil && !NavButton {
            BackStack?.push(LastRegion!);
        }
        LastRegion = mapView.region;
    }
    
    func mapView(mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        
        if LatLons.count > 0 && (LastRegionRefreshed == nil || !CDMapRegionStack.regionsAreSimilarIntolerant(LastRegionRefreshed!, region2: mapView.region)) {
            
            self.setTimerForPointsRefresh();
        }
        NavButton = false;
    }
    
    @objc private func refreshPoints() {
        
        _removeAllCoordsFromMap();
        addPoints(LatLons);
        LastRegionRefreshed = MapView.region;
    }

    private func addPoints(points: [(CLLocationCoordinate2D, CDMediaObjectWithLocation)]) {
        //print("Points Count " + String(points.count));
        let mapViewPoints = points.map
            {(MapView.convertCoordinate($0.0, toPointToView: MapView), $0.1)}.filter
            {CGRectContainsPoint(MapView.frame, $0.0)}.filter
            {!DateFilterUse || ($0.1.Date.isLessThanDate(DateFilterFinish) && $0.1.Date.isGreaterThan(DateFilterStart))}
        let mapViewCGPoints = mapViewPoints.map {$0.0};
        if mapViewPoints.count == 0 {
            return;
        }
        ProgressBar.hidden = false;
        ProgressBar.startAnimation(self);
        
        let lonelyPoints = mapViewPoints.filter {_countClosePoints($0.0, points: mapViewCGPoints) < FriendsNeededToNotBeLonely};
        let lonelyCoords = lonelyPoints.map {(MapView.convertPoint($0.0, toCoordinateFromView: MapView), $0.1)};
        _addLonelyCoordsToMap(lonelyCoords);
        
        let friendlyPoints = mapViewPoints.filter {_countClosePoints($0.0, points: mapViewCGPoints) >= FriendsNeededToNotBeLonely};
        if friendlyPoints.count == 0 {
            ProgressBar.hidden = true;
            return;
        }
        let (clusterCenters, maxD, clusterCounts, clusters) = Clustering!.kMeans(friendlyPoints);
        let clusterCoords = clusterCenters.map {(MapView.convertPoint($0.0, toCoordinateFromView: MapView), $0.1)};
        let clustersOfCoords = clusters.map({(c : Cluster) -> ClusterOfCoordinates in _convertClustersToCoordinate(c)});
        _addClusterCoordsToMap(clusterCoords, maxDs: maxD, clusterCounts: clusterCounts, clusters: clustersOfCoords);
        ProgressBar.hidden = true;
    }
    
    private func _convertClustersToCoordinate(cluster : Cluster) -> ClusterOfCoordinates {
        
        let center = MapView.convertPoint(cluster.Center, toCoordinateFromView: MapView);
        let points = cluster.Points.map({MapView.convertPoint($0, toCoordinateFromView: MapView)});
        return ClusterOfCoordinates.init(withCenter: center, andPoints: points);
    }
    
    private func _removeAllCoordsFromMap() {
        
        MapView.removeAnnotations(annotations);
        MapView.removeAnnotations(Overlays);
    }
    
    private func _addLonelyCoordsToMap(coords: [(CLLocationCoordinate2D, CDMediaObjectWithLocation)]) {
        
        for coord in coords {
            let annotation = ModifiedPinAnnotation(withDataLoad: MapAnnotation(withMediaObject: coord.1, andCoord:coord.0));
            annotation.coordinate = coord.0;
            annotations.append(annotation);
            MapView.addAnnotation(annotation);
        }
    }
    
    private func _addClusterCoordsToMap(coords: [(CLLocationCoordinate2D, [CDMediaObjectWithLocation])], maxDs: [Double], clusterCounts: [Int], clusters: [ClusterOfCoordinates]) {
        
        for i in 0...(coords.count - 1) {
            let coord = coords[i];
            let annotation = ModifiedClusterAnnotation(withDataLoad: MapAnnotation(withMediaObjects: coord.1, andCluster: clusters[i]));
            annotation.coordinate = coord.0;
            Overlays.append(annotation);
            MapView.addAnnotation(annotation);
        }
    }
    
    private func _countClosePoints(point: CGPoint, points: [CGPoint]) -> Int {
        
        let closeness = ClusterRadius;
        var count = 0;
        
        for pt in points {
            let distance = _pointDistance(point, pt: pt);
            if Double(distance) < closeness {
                count += 1;
            }
        }
        
        return count - 1;
    }
    
    private func _pointDistance(point: CGPoint, pt: CGPoint) -> CGFloat {
        
        let distance = pow(pow(point.x - pt.x, 2) + pow(point.y - pt.y, 2), 0.5);
        return distance;
    }
        
    func mapView(mapView: MKMapView, didSelectAnnotationView view: MKAnnotationView) {
        
        view.setSelected(true, animated: true);
        let annotation = view.annotation;        
        _processAnnotation(annotation!);
    }
    
    func _processAnnotation(annotation : MKAnnotation) {
        
        if (annotation as? ModifiedPinAnnotation) != nil {
            _processPhotoDataAnnotation(annotation);
        }
        
        if (annotation as? ModifiedClusterAnnotation) != nil {
            _processPhotoDataAnnotation(annotation);
        }
    }
    
    private func _processPhotoDataAnnotation(annotation: MKAnnotation) {
        
        let newRegion = ImageBrowserDel?.activateAnnotationView(annotation);
        
        if newRegion != nil {
            MapView.setRegion(newRegion!, animated: true);
        }
    }
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        
        if let anno = annotation as? ModifiedPinAnnotation {
            let pinView = MKPinAnnotationView.init(annotation: anno, reuseIdentifier: "\(anno.coordinate.latitude), \(anno.coordinate.longitude)");
            pinView.pinTintColor = NSColor.redColor();
            pinView.animatesDrop = false;
            return pinView;
        }
        
        if let anno = annotation as? ModifiedClusterAnnotation {
            let pinView = MKPinAnnotationView.init(annotation: anno, reuseIdentifier: "\(anno.coordinate.latitude), \(anno.coordinate.longitude)");
            pinView.pinTintColor = NSColor.blueColor();
            pinView.animatesDrop = false;
            return pinView;
        }
        
        if let anno = annotation as? MKPointAnnotation {
            if anno == HighlitPoint {
                let pinView = MKPinAnnotationView.init(annotation: anno, reuseIdentifier: "\(anno.coordinate.latitude), \(anno.coordinate.longitude)");
                pinView.pinTintColor = NSColor.yellowColor();
                YellowPinView = pinView;
                return pinView;
            }
        }
        
        return nil;
    }
    
    func mapView(mapView: MKMapView, didAddAnnotationViews views: [MKAnnotationView]) {
        
        if YellowPinView != nil && views.contains(YellowPinView!) {
            YellowPinView?.wantsLayer = true;
            YellowPinView!.layer?.zPosition = 10;
        }
    }
    
    func highlightPoint(withIndex: CLLocationCoordinate2D, yes: Bool) {
        
        if HighlitPoint != nil {
            MapView.removeAnnotation(HighlitPoint!);
            HighlitPoint = nil;
        }
        
        if yes {
            let coord = withIndex;
            HighlitPoint = MKPointAnnotation.init();
            HighlitPoint?.coordinate = coord;
            MapView.addAnnotation(HighlitPoint!);
            
            if(!MKMapRectContainsPoint(MapView.visibleMapRect, MKMapPointForCoordinate(coord))) {
                MapView.setCenterCoordinate(coord, animated: true);
            }
        }
    }
    
    private func _pixelsToDistance(pixels: Int) -> CLLocationDistance {
        
        let px1 = CGPointMake(MapView.frame.size.width / 2, MapView.frame.size.height / 2);
        let coord1 = MapView.convertPoint(px1, toCoordinateFromView: MapView);
        let px2 = CGPointMake(px1.x + CGFloat(pixels), px1.y);
        let coord2 = MapView.convertPoint(px2, toCoordinateFromView: MapView);
        
        let point1 = MKMapPointForCoordinate(coord1);
        let point2 = MKMapPointForCoordinate(coord2);
        let distance : CLLocationDistance = MKMetersBetweenMapPoints(point1, point2);
        
        return distance;
    }
    
    func setImageBrowserZoom(zoom : Float) {
        
        ImageBrowser.setZoomValue(zoom);
    }
    
    func forwardButtonPressed() {
        
        if let newRegion = ForwardStack?.pop() {
            BackStack?.push(MapView.region);
            NavButton = true;
            MapView.setRegion(newRegion, animated: true);
        }
    }
    
    func backButtonPressed() {
        
        if let newRegion = BackStack?.pop() {
            ForwardStack?.push(MapView.region);
            NavButton = true;
            MapView.setRegion(newRegion, animated: true);
            LastRegion = nil;
        }
    }
    
    func exportToCsv(path : NSURL, instructions : SaveDialogService.SaveCsvInstructions) {
        
        var objects : [CDMediaObjectWithLocation] = [];
        if instructions == SaveDialogService.SaveCsvInstructions.SaveAll {
            objects = LatLons.map {$0.1};
        }
        if instructions == SaveDialogService.SaveCsvInstructions.SaveVisible {
            let mapViewPoints = LatLons.map {(MapView.convertCoordinate($0.0, toPointToView: MapView), $0.1)}.filter {CGRectContainsPoint(MapView.frame, $0.0)};
            objects = mapViewPoints.map {$0.1};
        }
        objects = objects.filter {!DateFilterUse || ($0.Date.isLessThanDate(DateFilterFinish) && $0.Date.isGreaterThan(DateFilterStart))};
        
        let exporter = CDCsvExporter.init(withPath: path, andItems: objects);
        let result = exporter.export();
        let resultText = result ? "The CSV file has been saved." : "There was a problem saving the CSV file."
        let alert = NSAlert.init();
        alert.messageText = resultText;
        alert.runModal();
    }
    
    func updateDateFilter(withEarliestDate earliest : NSDate, andFuturemostDate latest : NSDate, useDateFilter : Bool) {
        
        DateFilterStart = earliest;
        DateFilterFinish = latest;
        DateFilterUse = useDateFilter;
        refreshPoints();
    }
    
    func horizontalSizeAdjusterWasMoved(deltaX: CGFloat) {
        let width = Double(self.view.frame.size.width);
        MapVsBrowser = min(max(MapVsBrowser + Double(deltaX) / width, 0.25), 0.75);
        self.viewDidLayout();
    }
    
    func mouseUp() {
        self.setTimerForPointsRefresh();
    }
    
    func selectPointsInit() {
        
        if RegionSelector != nil {
            RegionSelector?.removeFromSuperview();
            RegionSelector = nil;
        }
        RegionSelector = RectangularRegionSelector.init(frame: MapView.frame);
        RegionSelector!.Delegate = self;
        self.view.addSubview(RegionSelector!);
    }
    
    func rectangularRegionWasSelected(region: CGRect) {
        
        RegionSelector?.removeFromSuperview();
        RegionSelector = nil;
        
        let mapViewPoints = LatLons.map
            {(MapView.convertCoordinate($0.0, toPointToView: MapView), $0.1)}.filter
            {CGRectContainsPoint(region, $0.0)}
        if mapViewPoints.count == 0 {
            return;
        }
        let cdMediaObjects = mapViewPoints.map({(pt) -> CDMediaObjectWithLocation in
            return pt.1;
        });
        let coords = cdMediaObjects.map({mediaObject in return mediaObject.Location!});
        
        let cluster = ClusterOfCoordinates.init(withPoints: coords);
        let adHocDataLoad = MapAnnotation.init(withMediaObjects: mapViewPoints.map {$0.1}, andCluster: cluster);
        let adHocClusterAnnotation = ModifiedClusterAnnotation.init(withDataLoad: adHocDataLoad);
        self._processAnnotation(adHocClusterAnnotation);
    }
}

