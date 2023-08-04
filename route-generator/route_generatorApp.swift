//
//  route_generatorApp.swift
//  route-generator
//
//  Created by Christopher Simard on 7/24/23.
//

import UIKit
import MapKit
import SwiftUI
import Foundation
import MapboxMaps
import MapboxSearch
import MapboxSearchUI
import MapboxNavigation
import MapboxDirections
import MapboxCoreNavigation

// map controller wrapper
struct MapDisplayWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        // If needed, update any properties or UI of the UIViewController here
    }
}

// loading screen
struct LoadingScreen: View {
    @State private var isLoadingComplete = false
    
    var body: some View {
        ZStack {
            Color.black // Background color is set to white
            
            VStack {
                Spacer()
                Spacer()
                Text("Route Generator") // Your text goes here
                    .font(.largeTitle)
                    .foregroundColor(.white) // Text color is set to white
                Image("logo")
                Spacer()
            }
        }
        .edgesIgnoringSafeArea(.all) // Make the background color extend across the entire screen
        .onAppear {
            // Simulate some loading process or initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isLoadingComplete = true // Set this to true once loading is complete
            }
        }
        .fullScreenCover(isPresented: $isLoadingComplete, content: {
            // Once the loading is complete, present the MapViewControllerWrapper
            MapDisplayWrapper()
        })
    }
}

// controls map
class ViewController: UIViewController, UIGestureRecognizerDelegate {
    var navigationMapView: NavigationMapView!
    var routeOptions: NavigationRouteOptions?
    var routeResponse: MapboxDirections.Route?
    var routeWaypoints = [Waypoint]()
    var startingPoint = CLLocationCoordinate2D()
    var undoButton: UIButton!
    var distanceButton: UIButton!
    var isShowingMiles = true
    var routeDistance = 0.00
    var routeDistanceTitle: String?
    
    override func viewDidLoad() {
        // map loads by default on user location
        super.viewDidLoad()
        navigationMapView = NavigationMapView(frame: view.bounds)
        navigationMapView.userLocationStyle = .puck2D()
        navigationMapView.navigationCamera.viewportDataSource = NavigationViewportDataSource(navigationMapView.mapView, viewportDataSourceType: .raw)
        view.addSubview(navigationMapView)
        
        // render dot on map on tap
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        gestureRecognizer.delegate = self
        navigationMapView.mapView.addGestureRecognizer(gestureRecognizer)
        
        // add undo button
        let boldFont = UIFont.boldSystemFont(ofSize: 16)
        undoButton = UIButton(type: .system)
        undoButton.setTitle("Undo", for: .normal)
        undoButton.addTarget(self, action: #selector(undoButtonTapped), for: .touchUpInside)
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.backgroundColor = .white
        undoButton.layer.cornerRadius = 10
        undoButton.titleLabel?.font = boldFont
        undoButton.setTitleColor(.blue, for: .normal)
        undoButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        view.addSubview(undoButton)
        
        // add distance button
        distanceButton = UIButton(type: .system)
        getRouteDistanceTitle()
        distanceButton.addTarget(self, action: #selector(distanceButtonTapped), for: .touchUpInside)
        distanceButton.translatesAutoresizingMaskIntoConstraints = false
        distanceButton.backgroundColor = .white
        distanceButton.layer.cornerRadius = 10
        distanceButton.titleLabel?.font = boldFont
        distanceButton.setTitleColor(.blue, for: .normal)
        distanceButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        view.addSubview(distanceButton)

        // align buttons
        NSLayoutConstraint.activate([
            undoButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -25),
            undoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            distanceButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 25),
            distanceButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // render annotations on map
    @objc func handleTap(gestureRecognizer: UITapGestureRecognizer) {
        let location = gestureRecognizer.location(in: navigationMapView)
        let annotations = Array(navigationMapView.mapView.viewAnnotations.annotations.keys)
        let numAnnotations = annotations.count
        let numWaypoints = routeWaypoints.count
        
        // initialize green dot for origin on map
        if numAnnotations == 0 {
            addStartAnnotation(at: navigationMapView.mapView.mapboxMap.coordinate(for: location))
        } else if numWaypoints == 0 {
            let destination = navigationMapView.mapView.mapboxMap.coordinate(for: location)
            self.routeWaypoints = [Waypoint(coordinate: self.startingPoint), Waypoint(coordinate: destination)]
            calculateRoute()
        } else {
            extendRoute(point: navigationMapView.mapView.mapboxMap.coordinate(for: location))
        }
    }
    
    // add dot to annotations
    private func addStartAnnotation(at coordinate: CLLocationCoordinate2D) {
        let options = ViewAnnotationOptions(
            geometry: Point(coordinate),
            allowOverlap: true,
            anchor: .center
        )
        let annotationView = AnnotationView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        annotationView.coordinate = coordinate
        self.startingPoint = coordinate
        try? navigationMapView.mapView.viewAnnotations.add(annotationView, options: options)
    }
    
    // extend route with new waypoint
    func extendRoute(point: CLLocationCoordinate2D) {
        self.routeWaypoints.append(Waypoint(coordinate: point))
        calculateRoute()
    }
    
    // calculate route
    func calculateRoute() {

        let options = RouteOptions(waypoints: self.routeWaypoints, profileIdentifier: .walking)

        _ = Directions.shared.calculate(options) { [weak self] (session, result) in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                if let route = response.routes?.first {
                    // store the calculated route in a variable to use it later
                    self.routeResponse = route
                    // display the route on the map
                    self.drawRoute(route: route)
                    // update route distance
                    self.updateDistanceButton()
                } else {
                    print("No route found.")
                }
            case .failure(let error):
                print("Error calculating route: \(error.localizedDescription)")
            }
        }
    }
    
    // plot route on map
    func drawRoute(route: MapboxDirections.Route) {
        navigationMapView.show([route])
        navigationMapView.showWaypoints(on: route)
    }
    
    // get route distance
    func getRouteDistanceTitle() {
        if isShowingMiles {
            distanceButton.setTitle(String(format: "Distance: %.2f miles", routeDistance), for: .normal)
        } else {
            distanceButton.setTitle(String(format: "Distance: %.2f km", routeDistance * 1.60934), for: .normal)
        }
    }
    
    // undo function removes last added waypoint and redraws route
    @objc func undoButtonTapped() {
        
        // remove last waypoint
        if self.routeWaypoints.count > 1 {
            self.routeWaypoints.removeLast()
            navigationMapView.removeRoutes()
        }
        
        // calculate route if > 1 waypoint remains
        if self.routeWaypoints.count > 1 {
            navigationMapView.removeRoutes()
            calculateRoute()
        // only origin dot remains
        } else if self.routeWaypoints.count == 1 {
            self.routeWaypoints = []
            navigationMapView.removeRoutes()
            navigationMapView.removeWaypoints()
            routeResponse = nil
            updateDistanceButton()
        // remove origin dot
        } else {
            navigationMapView.mapView.viewAnnotations.removeAll()
        }
    }
    
    // updates route distance
    func updateDistanceButton() {
        // Update the distance button with the distance of the route
        let distance = routeResponse?.distance ?? 0.00
        let distanceInMeters = Measurement(value: distance, unit: UnitLength.meters).value
        routeDistance = distanceInMeters / 1609.34
        getRouteDistanceTitle()
    }

    @objc func distanceButtonTapped() {
        // Toggle between miles and kilometers when the button is tapped
        isShowingMiles = !isShowingMiles
        getRouteDistanceTitle()
    }
    
}

// green dot starting point
@IBDesignable
class AnnotationView: UIView {
        
    // property storing coordinate of point
    var coordinate: CLLocationCoordinate2D?
    
    // draw point
    override func draw(_ rect: CGRect) {
        var path = UIBezierPath()
        path = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 7.5, height: 7.5))
        UIColor.green.setStroke()
        UIColor.green.setFill()
        path.lineWidth = 5
        path.stroke()
        path.fill()
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        // Set the background color to transparent
        backgroundColor = UIColor.clear
    }
}

// run app
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            LoadingScreen()
        }
    }
}
