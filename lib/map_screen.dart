import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Same WAQI token used in main.dart — duplicated here so this screen
// can independently query any tapped location without needing to pass
// the token through multiple screens.
const String _waqiToken = "8080f75734a2bf5a87655e51133e6e64a392408f";

/// Shows the monitoring station's location on an OpenStreetMap-based map,
/// with a colour-coded marker for the current AQI. Users can also tap
/// anywhere on the map to fetch and display AQI for that location.
class MapScreen extends StatefulWidget {
  final double lat;
  final double lon;
  final String cityName;
  final int aqi;
  final Color aqiColor;

  const MapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.cityName,
    required this.aqi,
    required this.aqiColor,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  double _currentZoom = 12;

  // State for whatever point the user taps on the map
  LatLng? _tappedPoint;
  bool _tappedLoading = false;
  String? _tappedError;
  int? _tappedAqi;
  String? _tappedName;

  void _zoomIn() {
    _currentZoom = (_currentZoom + 1).clamp(2, 18);
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  void _zoomOut() {
    _currentZoom = (_currentZoom - 1).clamp(2, 18);
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  void _recenter() {
    _currentZoom = 12;
    _mapController.move(LatLng(widget.lat, widget.lon), _currentZoom);
  }

  Color _aqiColorFor(int aqi) {
    if (aqi <= 50) return Colors.green;
    if (aqi <= 100) return Colors.yellow.shade700;
    if (aqi <= 150) return Colors.orange;
    if (aqi <= 200) return Colors.red;
    if (aqi <= 300) return Colors.purple;
    return Colors.brown.shade900;
  }

  String _categoryFor(int aqi) {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive Groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  // Called when the user taps anywhere on the map
  Future<void> _onMapTap(TapPosition tapPosition, LatLng point) async {
    setState(() {
      _tappedPoint = point;
      _tappedLoading = true;
      _tappedError = null;
      _tappedAqi = null;
      _tappedName = null;
    });

    try {
      final url = Uri.parse(
          'https://api.waqi.info/feed/geo:${point.latitude};${point.longitude}/?token=$_waqiToken');
      final response = await http.get(url);
      final json = jsonDecode(response.body);

      if (json['status'] != 'ok') {
        throw Exception('No monitoring station data available here.');
      }

      final data = json['data'];
      setState(() {
        _tappedAqi = data['aqi'];
        _tappedName = data['city']?['name'] ?? 'Unknown location';
        _tappedLoading = false;
      });
    } catch (e) {
      setState(() {
        _tappedError = 'No data available for this location.';
        _tappedLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.lat, widget.lon);

    return Scaffold(
      appBar: AppBar(
        title: Text('Map - ${widget.cityName}'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: point,
              initialZoom: _currentZoom,
              onTap: _onMapTap,
              // Pan: click-and-drag on emulator. Zoom: buttons below
              // (mouse has no pinch gesture) or Ctrl+scroll if supported.
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.air_quality_app',
              ),
              MarkerLayer(
                markers: [
                  // Original searched-city marker
                  Marker(
                    point: point,
                    width: 90,
                    height: 70,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.aqiColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: Text(
                            'AQI ${widget.aqi}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(Icons.location_on,
                            color: widget.aqiColor, size: 32),
                      ],
                    ),
                  ),
                  // Marker for whatever the user just tapped, if any
                  if (_tappedPoint != null)
                    Marker(
                      point: _tappedPoint!,
                      width: 90,
                      height: 70,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _tappedLoading
                                  ? Colors.grey
                                  : (_tappedAqi != null
                                      ? _aqiColorFor(_tappedAqi!)
                                      : Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: Text(
                              _tappedLoading
                                  ? '...'
                                  : (_tappedAqi != null
                                      ? 'AQI $_tappedAqi'
                                      : '?'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: _tappedLoading
                                ? Colors.grey
                                : (_tappedAqi != null
                                    ? _aqiColorFor(_tappedAqi!)
                                    : Colors.grey),
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Zoom controls
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoomIn',
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoomOut',
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  onPressed: _recenter,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          // Info card showing details for the tapped location
          if (_tappedPoint != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _tappedLoading
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Fetching AQI for this location...'),
                          ],
                        )
                      : _tappedError != null
                          ? Text(_tappedError!,
                              style: const TextStyle(color: Colors.red))
                          : Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _aqiColorFor(_tappedAqi ?? 0),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _tappedName ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'AQI ${_tappedAqi ?? "-"} · ${_categoryFor(_tappedAqi ?? 0)}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}