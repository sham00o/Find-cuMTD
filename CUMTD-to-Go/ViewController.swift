//
//  ViewController.swift
//  CUMTD-to-Go
//
//  Created by Samuel Liu on 9/28/15.
//  Copyright © 2015 iSam. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation

class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    
    // Current CUMTD API Version
    let version = "v2.2"
    
    // API Developer Key
    let key = "6a6db804d1a94f479f010f9de654cf90"
    
    var locationManager : CLLocationManager!
    var locations : [CLLocationCoordinate2D]!
    var destPin : MKPointAnnotation!
    
    var points = Array<BusPoint>()
    var stops = Dictionary<String, String>()
    var coords = Dictionary<String, CLLocationCoordinate2D>()
    
    @IBOutlet weak var timestamp: UILabel!
    @IBOutlet weak var map: MKMapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if (CLLocationManager.locationServicesEnabled())
        {
            locationManager = CLLocationManager()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestAlwaysAuthorization()
            locationManager.startUpdatingLocation()
            map.showsUserLocation = true

        }
        
        configureNavBar()
        
        timestamp.text = ""
        requestMTDStops()
    }
    
    @IBAction func request(sender: AnyObject) {
        points = Array<BusPoint>()
        requestMTDBuses()
    }
    
    func configureNavBar() {
        self.navigationController?.navigationBar.barTintColor = UIColor(red: 0/255.0, green: 32/255.0, blue: 91/255.0, alpha: 1.0)
        self.navigationController?.navigationBar.titleTextAttributes = [NSForegroundColorAttributeName: UIColor.whiteColor(), NSFontAttributeName: UIFont(name: "AvenirNext-Regular", size: 20)!]
        self.navigationController!.navigationBar.barStyle = UIBarStyle.Default
        self.navigationController?.navigationBar.shadowImage = UIImage(named: " ")
        UIApplication.sharedApplication().statusBarStyle = .LightContent
    }
    
    func requestMTDStops() {
        let url = NSURL(string: "https://developer.cumtd.com/api/v2.2/json/GetStops?key=\(key)")
        let request = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "GET"
        
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: {
            data, response, error in
            
            if let dict = (try? NSJSONSerialization.JSONObjectWithData(data!, options:NSJSONReadingOptions.MutableContainers)) as? NSDictionary {
                
                //
                // Store stop ids and stop names in dictionary to look up later
                //
                if let stops = dict["stops"] {
                    for stop in stops as! NSArray {
                        let stopDict = stop as! NSDictionary
                        let stopPoints = stopDict["stop_points"] as! NSArray
                        for stops in stopPoints {
                            let stopID = stops["stop_id"] as! String
                            let stopName = stops["stop_name"] as! String
                            let lat = stops["stop_lat"] as! CLLocationDegrees
                            let lon = stops["stop_lon"] as! CLLocationDegrees
                            self.stops[stopID] = stopName
                            self.coords[stopName] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        }
                    }
                }
            }
            self.requestMTDBuses()
        })
        task.resume()
    }
    
    func requestMTDBuses() {
        let url = NSURL(string: "https://developer.cumtd.com/api/\(version)/json/GetVehicles?key=\(key)")
        let request = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "GET"
        
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: {
            data, response, error in
            
            if let dict = (try? NSJSONSerialization.JSONObjectWithData(data!, options:NSJSONReadingOptions.MutableContainers)) as? NSDictionary {
                
                if let buses = dict["vehicles"] {

                    dispatch_async(dispatch_get_main_queue(), {
                        self.parseBusInformation(buses as! NSArray)
                    })

                }
            }
        })
        task.resume()

    }
    
    func parseBusInformation(buses: NSArray) {
        // remove existing annotations
        let annotationsToRemove = map.annotations.filter { $0 !== map.userLocation }
        map.removeAnnotations( annotationsToRemove )
        
        for bus in buses {
            let busDict = bus as! NSDictionary
            let locationDict = busDict["location"] as! NSDictionary
            let lat = locationDict["lat"] as! CLLocationDegrees
            let lon = locationDict["lon"] as! CLLocationDegrees
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            markBusLocations(coord, bus: busDict)
        }
    }
    
    func markBusLocations(coord: CLLocationCoordinate2D, bus: NSDictionary) {
        let tripDict = bus["trip"] as! NSDictionary
        let route = tripDict["route_id"] as! String
        let direction = tripDict["direction"] as! String
        if let nextStop = bus["next_stop_id"] as? String {
            if let stop = stops[nextStop] {
                if let dest = coords[stop] {
                    if let time = bus["last_updated"] as? String {
                        let timestamp = parseDate(time)

                        let point = BusPoint()
                        point.coordinate = coord
                        point.title = "\(route) \(direction)"
                        point.subtitle = "Next stop: \(stop)"
                        point.destinationCoord = dest
                        point.routeColor = "\(route)"
                        point.timestamp = timestamp
                        self.points.append(point)
                        self.map.addAnnotation(point)
                    }
                }
            }
        }
    }
    
    // Convert UTC date string to NSDate and reformat into local time date string
    func parseDate(date: String) -> String {
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.timeZone = NSTimeZone(name: "UTC")
        let convertedDate = dateFormatter.dateFromString(date)
        dateFormatter.dateFormat = "h:mm:ss a"
        dateFormatter.timeZone = NSTimeZone.localTimeZone()
        let timestamp = dateFormatter.stringFromDate(convertedDate!)
        return timestamp
    }

    // MARK: - Location Manager Methods
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last as CLLocation!
        
        let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        
        self.map.setRegion(region, animated: true)
        
        self.locationManager.stopUpdatingLocation()
    }
    
    // MARK: - Mapview Methods
    
    func mapView(mapView: MKMapView, didSelectAnnotationView view: MKAnnotationView) {
        
        let curPin = view.annotation as! BusPoint
        
        for point in points {
            if point != curPin {
                let annotation = point as MKAnnotation
                map.removeAnnotation(annotation)
            }
        }
        
        timestamp.text = "last updated: \(curPin.timestamp)"
        destPin = MKPointAnnotation()
        destPin.coordinate = curPin.destinationCoord
        destPin.title = curPin.subtitle
        self.map.addAnnotation(destPin)
    }
    
    func mapView(mapView: MKMapView, didDeselectAnnotationView view: MKAnnotationView) {
        
        let curPin = view.annotation as! BusPoint
        
        timestamp.text = ""
        
        self.map.removeAnnotation(destPin)
        for point in points {
            if point != curPin {
                let annotation = point as MKAnnotation
                map.addAnnotation(annotation)
            }
        }
    }
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        
        if annotation is MKUserLocation {
            return nil
        }
        
        let pin = MKPinAnnotationView()
        pin.animatesDrop = true
        pin.canShowCallout = true
        if let point = annotation as? BusPoint {
            if point.routeColor.containsString("GREEN") {
                pin.pinTintColor = UIColor(red: 0/255.0, green: 128/255.0, blue: 99/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("SILVER") {
                pin.pinTintColor = UIColor(red: 204/255.0, green: 204/255.0, blue: 204/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("RED") {
                pin.pinTintColor = UIColor(red: 237/255.0, green: 28/255.0, blue: 36/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("YELLOW") {
                pin.pinTintColor = UIColor(red: 252/255.0, green: 238/255.0, blue: 31/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("BLUE") {
                pin.pinTintColor = UIColor(red: 53/255.0, green: 92/255.0, blue: 170/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("GOLD") {
                pin.pinTintColor = UIColor(red: 197/255.0, green: 151/255.0, blue: 46/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("LAVENDAR") {
                pin.pinTintColor = UIColor(red: 167/255.0, green: 139/255.0, blue: 192/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("GREY") {
                pin.pinTintColor = UIColor(red: 128/255.0, green: 130/255.0, blue: 133/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("AIR") {
                pin.pinTintColor = UIColor(red: 104/255.0, green: 182/255.0, blue: 229/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("BRONZE") {
                pin.pinTintColor = UIColor(red: 158/255.0, green: 137/255.0, blue: 102/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("BROWN") {
                pin.pinTintColor = UIColor(red: 130/255.0, green: 86/255.0, blue: 34/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("LIME") {
                pin.pinTintColor = UIColor(red: 178/255.0, green: 210/255.0, blue: 53/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("NAVY") {
                pin.pinTintColor = UIColor(red: 43/255.0, green: 48/255.0, blue: 136/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("PINK") {
                pin.pinTintColor = UIColor(red: 255/255.0, green: 191/255.0, blue: 255/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("RAVEN") {
                pin.pinTintColor = UIColor(red: 0/255.0, green: 0/255.0, blue: 0/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("ORANGE") {
                pin.pinTintColor = UIColor(red: 249/255.0, green: 159/255.0, blue: 42/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("RUBY") {
                pin.pinTintColor = UIColor(red: 235/255.0, green: 0/255.0, blue: 139/255.0, alpha: 1.0)
            } else if point.routeColor.containsString("TEAL") {
                pin.pinTintColor = UIColor(red: 0/255.0, green: 105/255.0, blue: 145/255.0, alpha: 1.0)
            } else {
                pin.pinTintColor = UIColor(red: 90/255.0, green: 29/255.0, blue: 90/255.0, alpha: 1.0)
            }
        } else {
            pin.pinTintColor = UIColor.redColor()
        }
        
        return pin
    }


}

class BusPoint : MKPointAnnotation {
    var routeColor : String!
    var destinationCoord : CLLocationCoordinate2D!
    var timestamp : String!
}

