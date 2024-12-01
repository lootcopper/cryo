import SwiftUI
import CoreLocation
import Firebase
import FirebaseDatabase
import FirebaseAuth

struct Ride: Identifiable {
    var id: String
     var pickupLocation: String
     var dropLocation: String
     var status: String = "requested"
     var coordinate: CLLocationCoordinate2D
     var requestedBy: String
     var userName: String
     var schoolName: String
     var userEmail: String
     var phoneNumber: String
    

    init(id: String = UUID().uuidString, pickupLocation: String, dropLocation: String, status: String = "requested", coordinate: CLLocationCoordinate2D, requestedBy: String, userName: String, schoolName: String, phoneNumber: String, userEmail: String) {
         self.id = id
         self.pickupLocation = pickupLocation
         self.dropLocation = dropLocation
         self.status = status
         self.coordinate = coordinate
         self.requestedBy = requestedBy
         self.userName = userName
         self.schoolName = schoolName
         self.phoneNumber = phoneNumber
         self.userEmail = userEmail
     }
 }


class RideManager: ObservableObject {
    @Published var rides: [Ride] = [] // Store all ride requests
    @Published var acceptedRide: Ride? // Track the currently accepted ride
    @Published var alertMessage: String = ""
    
    
    func didUserRequestRide(userEmail: String, ride: Ride) -> Bool {
        return ride.requestedBy == userEmail
    }

    private let dbRef = Database.database().reference()

    init() {
        fetchRidesFromRealtimeDatabase()
        listenForRideUpdates()
    }
    
    func sendAlertToRider(riderEmail: String) {
           DispatchQueue.main.async {
               self.alertMessage = "Your ride has been accepted!"
               print("Alert to \(riderEmail): Your ride has been accepted!")
               // Integrate additional UI updates here
           }
       }

       // Listen for ride updates in Realtime Database
       private func listenForRideUpdates() {
           dbRef.child("rideRequests").observe(.childChanged) { snapshot in
               guard let rideData = snapshot.value as? [String: Any],
                     let status = rideData["status"] as? String,
                     let requestedBy = rideData["requestedBy"] as? String else {
                   print("Error: Ride data or status not found")
                   return
               }

               // Check if the status is "accepted"
               if status == "accepted" {
                   let riderEmail = rideData["requestedBy"] as? String ?? "Unknown"
                   print("Ride status has been accepted for \(riderEmail)")
                   // Send an in-app alert to the rider
                   self.sendAlertToRider(riderEmail: riderEmail)
               }
           }
       }

       // Fetch ride requests from Realtime Database
       func fetchRidesFromRealtimeDatabase() {
           dbRef.child("rideRequests").observe(.value) { snapshot in
               var fetchedRides: [Ride] = []
               for child in snapshot.children.allObjects as! [DataSnapshot] {
                   if let rideData = child.value as? [String: Any],
                      let ride = self.parseRideData(rideData, id: child.key) {
                       fetchedRides.append(ride)
                   }
               }
               self.rides = fetchedRides
           }
       }

       private func parseRideData(_ data: [String: Any], id: String) -> Ride? {
           guard
               let pickupLocation = data["pickupLocation"] as? String,
               let dropLocation = data["dropLocation"] as? String,
               let status = data["status"] as? String,
               let latitude = data["latitude"] as? Double,
               let longitude = data["longitude"] as? Double,
               let requestedBy = data["requestedBy"] as? String,
               let userName = data["userName"] as? String,
               let schoolName = data["schoolName"] as? String,
               let phoneNumber = data["phoneNumber"] as? String,
               let userEmail = data["userEmail"] as? String
           else {
               return nil
           }

           let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
           return Ride(id: id, pickupLocation: pickupLocation, dropLocation: dropLocation, status: status, coordinate: coordinate, requestedBy: requestedBy, userName: userName, schoolName: schoolName, phoneNumber: phoneNumber, userEmail: userEmail)
       }

       // Request a new ride and save to Realtime Database
       func requestRide(pickupLocation: String, dropLocation: String, coordinate: CLLocationCoordinate2D) {
           print("Requesting a new ride...")

           // Ensure user is authenticated
           guard let user = Auth.auth().currentUser else {
               print("User not authenticated")
               return
           }

           // Get authenticated user's email
           let userEmail = user.email ?? "Unknown"
           print("Authenticated user email: \(userEmail)")

           // Fetch user profile from Firestore
           let db = Firestore.firestore()
           let docRef = db.collection("users").document(userEmail)
           docRef.getDocument { document, error in
               if let document = document, document.exists {
                   let data = document.data() ?? [:]
                   let userName = data["userName"] as? String ?? "Unknown"
                   let schoolName = data["schoolName"] as? String ?? "Unknown"
                   let phoneNumber = data["phoneNumber"] as? String ?? "Unknown";

                   // Log fetched values from Firestore
                   print("Fetched from Firestore: userName = \(userName), schoolName = \(schoolName), phoneNumber = \(phoneNumber)")

                   // Generate a new ID for the ride
                   let newRideID = UUID().uuidString

                   let newRide = Ride(
                       id: newRideID,
                       pickupLocation: pickupLocation,
                       dropLocation: dropLocation,
                       coordinate: coordinate,
                       requestedBy: userEmail,
                       userName: userName,
                       schoolName: schoolName,
                       phoneNumber: phoneNumber,
                       userEmail: userEmail
                   )

                   // Save the ride to Realtime Database
                   let rideData: [String: Any] = [
                       "pickupLocation": newRide.pickupLocation,
                       "dropLocation": newRide.dropLocation,
                       "status": newRide.status,
                       "requestedBy": newRide.requestedBy,
                       "userName": newRide.userName,
                       "schoolName": newRide.schoolName,
                       "phoneNumber": newRide.phoneNumber,
                       "userEmail": newRide.userEmail,  // Added userEmail field
                       "latitude": newRide.coordinate.latitude,  // Added latitude
                       "longitude": newRide.coordinate.longitude  // Added longitude
                   ]

                   self.dbRef.child("rideRequests").child(newRideID).setValue(rideData) { error, _ in
                       if let error = error {
                           print("Error saving ride: \(error)")
                       } else {
                           self.rides.append(newRide)
                           print("New ride requested by \(userName) from \(pickupLocation) to \(dropLocation).")
                       }
                   }
               } else {
                   print("Error fetching user profile from Firestore: \(error?.localizedDescription ?? "Unknown error")")
               }
           }
       }

       // Accept a ride and update status in Realtime Database
       func acceptRide(_ ride: Ride) {
           if let index = rides.firstIndex(where: { $0.id == ride.id }) {
               rides[index].status = "accepted"
               acceptedRide = rides[index]
               dbRef.child("rideRequests").child(ride.id).updateChildValues(["status": "accepted"]) { error, _ in
                   if let error = error {
                       print("Error updating ride status: \(error)")
                   } else {
                       print("Ride status updated to accepted for \(self.rides[index].userName)")
                   }
               }
           }
       }

       // Start the ride and update status in Realtime Database
       func startRide(_ ride: Ride) {
           if let index = rides.firstIndex(where: { $0.id == ride.id }) {
               rides[index].status = "inProgress"
               acceptedRide = rides[index]

               dbRef.child("rideRequests").child(ride.id).updateChildValues(["status": "inProgress"]) { error, _ in
                   if let error = error {
                       print("Error updating ride status: \(error)")
                   } else {
                       print("Ride status updated to in-progress.")
                   }
               }
           }
       }

       // Complete the ride and update status in Realtime Database
       func completeRide(_ ride: Ride) {
           if let index = rides.firstIndex(where: { $0.id == ride.id }) {
               rides[index].status = "completed"
               acceptedRide = nil

               dbRef.child("rideRequests").child(ride.id).updateChildValues(["status": "completed"]) { error, _ in
                   if let error = error {
                       print("Error updating ride status: \(error)")
                   } else {
                       print("Ride status updated to completed.")
                   }
               }
           }
       }
   }
