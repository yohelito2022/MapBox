import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:mapbox_gl/mapbox_gl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' as DotEnv;
import 'package:mapbox_with_navigation/utils/request_location_permission.dart';
import 'package:provider/provider.dart';

import './utils/add_markers_to_map.dart';
import './model/location_details.dart';
import './providers/mapProvider.dart';
import './widgets/pin_details.dart';
import './widgets/path_widget.dart';
import './utils/request_path.dart';
import './widgets/change_loc.dart';

class FullMap extends StatefulWidget {
  const FullMap();

  @override
  State createState() => FullMapState();
}

class FullMapState extends State<FullMap> {
  MapboxMapController mapController;
  MapState mapState;
  Location _location = Location();
  LocationData userLoc;
  Symbol userLocSymbol;
  StreamSubscription _locationSubscription;
  bool _loading = false;
  Symbol selectedMarker;
  LocationDetails _startLocation;
  LocationDetails _destLocation;

  ///Añadir marcador/símbolo en la ubicación del usuario o
  ///actualiza la ubicación del símbolo si existe
  Future<void> updateUserLoc(LocationData newLocalData) async {
    final newLoc = LatLng(newLocalData.latitude, newLocalData.longitude);
    if (userLocSymbol != null) {
      mapController.updateSymbol(
          userLocSymbol,
          SymbolOptions(
            geometry: newLoc,
          ));
    } else {
      print('dsfsdfsdfsdfsdfdsfsdfewafsfsaf');
      userLocSymbol = await mapController.addSymbol(
        SymbolOptions(
          geometry: newLoc,
          textField: 'You',
          textOffset: Offset(0, 2),
          iconImage: 'assets/icons/location_pin.png',
          iconSize: 0.5,
        ),
      );
    }
    userLoc = newLocalData;
  }

  ///Solicitar permisos de ubicación de usuario: agregue un símbolo en la ubicación de uso
  ///y establecer la escucha de la ubicación del usuario (si se otorga el acceso)
  Future<void> getCurrentLocation() async {
    userLoc = await requestLicationPermissionAndUserLoc();
    if (userLoc != null) {
      await updateUserLoc(userLoc);
      mapController.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(userLoc.latitude, userLoc.longitude), 16));
    }
    if (_locationSubscription != null) {
      _locationSubscription.cancel();
    }
    _locationSubscription = _location.onLocationChanged
        .listen((LocationData currentLocation) async {
      await updateUserLoc(currentLocation);
    });
  }

  Future<void> _onMapCreated(MapboxMapController controller) async {
    mapController = context.read<MapProvider>().setController(controller);

    //si se toca, actualizará el color del símbolo a rojo
    // y establece el marcador seleccionado en el marcador tocado
    //también cambiará el estado del mapa a MapState.Pinlocation
    mapController.onSymbolTapped.add((marker) async {
      if (marker != userLocSymbol) {
        if (selectedMarker != null) {
          clearAll();
        }
        selectedMarker = marker;
        mapController.updateSymbol(
          marker,
          SymbolOptions(iconImage: 'assets/icons/location_pin_red.png'),
        );
        context.read<MapProvider>().changeMapstate(MapState.Pinlocation);
      }
    });
    // los marcadores están codificados en el archivo de la función
    addYourMarkersToMap(mapController);
  }

  void _onMapLongClick(Point<double> point, LatLng coordinates) async {
    print(coordinates);
    if (mapState == MapState.None || mapState == MapState.ChangingLocation) {
      selectedMarker = await mapController.addSymbol(
        SymbolOptions(
          geometry: coordinates,
          iconImage: 'assets/icons/location_pin_red.png',
          iconSize: 0.5,
        ),
      );
    }
    if (mapState != MapState.ChangingLocation)
      context.read<MapProvider>().changeMapstate(MapState.Pinlocation);
  }

  @override
  Widget build(BuildContext context) {
    mapState = context.watch<MapProvider>().mapState;
    return Scaffold(
      body: Stack(
        children: [
          MapboxMap(
            accessToken: DotEnv.env['MAPBOX_ACCESS_TOKEN'],
            onMapCreated: _onMapCreated,
            onMapLongClick: _onMapLongClick,
            onMapClick: (point, coordinates) {
              if (mapState != MapState.ShowingPath) clearAll();
            },
            zoomGesturesEnabled: true,
            initialCameraPosition: const CameraPosition(
                target: LatLng(33.3152, 44.3661), zoom: 14.0),
          ),
          PathWidget(
            startLocation: _startLocation,
            destLocation: _destLocation,
          ),
          ChangingLocation(setNewLoc: setNewLoc),
          PinDetails(marker: selectedMarker, showPath: showPath),
          SafeArea(
            child: Container(
                width: MediaQuery.of(context).size.width - 20,
                margin: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Theme.of(context).accentColor,
                ),
                height: 60,
                child: Stack(
                  // mainAxisAlignment: MainAxisAlignment.center,
                  // crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    if (mapState != MapState.None)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextButton(
                            child: Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              if (mapState != MapState.ChangingLocation)
                                clearAll();
                              else
                                showPath(_destLocation);
                            },
                          ),
                        ),
                      ),
                    _loading
                        ? Center(
                            child: CircularProgressIndicator(
                            backgroundColor: Colors.blue,
                            strokeWidth: 6,
                          ))
                        : Container(
                            alignment: Alignment.center,
                            child: Text(
                              'Mapbox Map',
                              // textAlign: TextAlign.center,
                              style:
                                  TextStyle(fontSize: 25, color: Colors.white),
                            ),
                          ),
                  ],
                )),
          )
        ],
      ),
      floatingActionButton: mapState == MapState.None
          ? FloatingActionButton(
              child: Icon(Icons.location_searching),
              onPressed: getCurrentLocation,
            )
          : null,
    );
  }

  //Esta función debe llamarse después de que el usuario seleccione
  //la nueva ubicación de inicio/destino
  //Esta función es responsable de establecer el nuevo valor de inicio/destino
  //basado en ChangingLocationState y mostrando la nueva ruta
  void setNewLoc() {
    final temploc = LocationDetails(
      coordinates: selectedMarker.options.geometry,
      name: selectedMarker.options.textField ?? "Droped pin",
    );
    final changLocState = context.read<MapProvider>().changLocState;
    if (changLocState == ChangingLocationState.StartingLoc) {
      if (temploc != _destLocation) _startLocation = temploc;
    } else {
      _destLocation = temploc;
    }

    showPath(_destLocation, startLocation: _startLocation);
  }

  ///toma la ubicación de inicio y la ubicación de destino y dibuja la ruta
  ///si la ubicación de inicio es nula, por defecto será la ubicación del usuario si no es nula
  ///Se requiere la ubicación de destino al llamar a la func
  Future<void> showPath(
    LocationDetails destLocation, {
    LocationDetails startLocation,
  }) async {
    _destLocation = destLocation;

    if (startLocation != null) {
      _startLocation = startLocation;
    } else {
      _startLocation = userLoc != null
          ? LocationDetails(
              coordinates: LatLng(userLoc.latitude, userLoc.longitude),
              name: 'My Location')
          : LocationDetails(
              coordinates: null, name: 'Select starting location');
    }

    context.read<MapProvider>().changeMapstate(MapState.ShowingPath);
    if (_destLocation.coordinates != null &&
        _startLocation.coordinates != null) {
      setState(() => _loading = true);
      final path = await requestpathfromMapBox(
          from: _startLocation.coordinates, to: _destLocation.coordinates);
      if (path.length > 0) {
        await mapController.addLine(
          LineOptions(
            geometry: path,
            lineColor: "#8196F5",
            lineWidth: 4.0,
            lineOpacity: 1.0,
          ),
        );
      }
      setState(() => _loading = false);
    }
  }

  ///Esta función se encarga de limpiar cualquier ruta y elimina
  ///el marcador seleccionado (si no es primario)
  /// del mapa y establecerá mapState en [MapState.None]
  ///Nota: si el marcador es primario, cambiará su color de nuevo a negro
  Future<void> clearAll() async {
    mapController.clearLines();
    if (selectedMarker != null) if (selectedMarker.options.textField == null ||
        !selectedMarker.options.textField.contains('loc'))
      await mapController.removeSymbol(selectedMarker);
    else
      mapController.updateSymbol(selectedMarker,
          SymbolOptions(iconImage: 'assets/icons/location_pin.png'));
    context.read<MapProvider>().changeMapstate(MapState.None);
    selectedMarker = null;
  }
}
