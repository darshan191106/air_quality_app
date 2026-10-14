import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'chat_screen.dart';
import 'map_screen.dart';
import 'notification_service.dart';

const String waqiToken = "8080f75734a2bf5a87655e51133e6e64a392408f";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const AirQualityApp());
}

class AirQualityApp extends StatelessWidget {
  const AirQualityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Air Quality Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;

  int? _aqi;
  String _cityName = "";
  Map<String, dynamic>? _pollutants;
  List<Map<String, dynamic>>? _pm25Forecast; // daily avg PM2.5 trend
  List<double>? _geo; // [lat, lon] of the station, for the map view
  String? _fallbackNotice; // shown when a searched city had no data

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAirQuality(city: 'chennai');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Main loader: if [city] is provided, search that city directly.
  // Otherwise, use GPS location, falling back to a default city if the
  // geo-coordinate lookup fails (e.g. no nearby monitoring station).
  Future<void> _loadAirQuality({String? city}) async {
    setState(() {
      _loading = true;
      _error = null;
      _fallbackNotice = null;
    });

    try {
      Map<String, dynamic> data;

      if (city != null && city.trim().isNotEmpty) {
        try {
          data = await _fetchAqiDataByCity(city.trim());
        } catch (e) {
          // Searched city has no station: auto-fallback to a nearby major city
          const fallbackCity = 'chennai';
          data = await _fetchAqiDataByCity(fallbackCity);
          _fallbackNotice =
              'No data found for "${city.trim()}". Showing nearby major city instead.';
        }
      } else {
        Position position = await _determinePosition();
        try {
          data = await _fetchAqiData(position.latitude, position.longitude);
        } catch (e) {
          // Fallback: geo lookup failed (no nearby station), try a default city
          data = await _fetchAqiDataByCity('chennai');
        }
      }

      // Extract PM2.5 daily forecast/history for the trend chart, if present
      List<Map<String, dynamic>>? pm25Trend;
      try {
        final forecast = data['forecast']?['daily']?['pm25'];
        if (forecast != null) {
          pm25Trend = List<Map<String, dynamic>>.from(forecast);
        }
      } catch (_) {
        pm25Trend = null;
      }

      List<double>? geo;
      try {
        final rawGeo = data['city']['geo'];
        if (rawGeo != null) {
          geo = List<double>.from(
              (rawGeo as List).map((e) => (e as num).toDouble()));
        }
      } catch (_) {
        geo = null;
      }

      setState(() {
        _aqi = data['aqi'];
        _cityName = data['city']['name'] ?? "Unknown location";
        _pollutants = data['iaqi'];
        _pm25Forecast = pm25Trend;
        _geo = geo;
        _loading = false;
      });

      // Alert module: notify the user if the air here is unhealthy
      final currentAqi = _aqi ?? 0;
      NotificationService.maybeAlert(
        place: _cityName,
        aqi: currentAqi,
        category: _aqiCategory(currentAqi),
        advice: _healthAdvice(currentAqi),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission permanently denied. Enable it in app settings.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
      forceAndroidLocationManager: true,
    );
  }

  Future<Map<String, dynamic>> _fetchAqiData(double lat, double lon) async {
    final url = Uri.parse(
        'https://api.waqi.info/feed/geo:$lat;$lon/?token=$waqiToken');
    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to reach AQI server (${response.statusCode})');
    }

    final json = jsonDecode(response.body);
    if (json['status'] != 'ok') {
      throw Exception('API error: ${json['data'] ?? 'unknown error'}');
    }

    return json['data'];
  }

  Future<Map<String, dynamic>> _fetchAqiDataByCity(String city) async {
    final url =
        Uri.parse('https://api.waqi.info/feed/$city/?token=$waqiToken');
    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to reach AQI server (${response.statusCode})');
    }

    final json = jsonDecode(response.body);
    if (json['status'] != 'ok') {
      throw Exception(
          'City not found. Try a nearby major city (e.g. chennai, delhi, mumbai).');
    }

    return json['data'];
  }

  String _aqiCategory(int aqi) {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive Groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  Color _aqiColor(int aqi) {
    if (aqi <= 50) return Colors.green;
    if (aqi <= 100) return Colors.yellow.shade700;
    if (aqi <= 150) return Colors.orange;
    if (aqi <= 200) return Colors.red;
    if (aqi <= 300) return Colors.purple;
    return Colors.brown.shade900;
  }

  String _healthAdvice(int aqi) {
    if (aqi <= 50) return 'Air quality is good. Enjoy outdoor activities.';
    if (aqi <= 100) {
      return 'Acceptable air quality. Unusually sensitive people should consider reducing prolonged outdoor exertion.';
    }
    if (aqi <= 150) {
      return 'Sensitive groups (children, elderly, asthma) should limit prolonged outdoor exertion.';
    }
    if (aqi <= 200) {
      return 'Everyone may begin to experience health effects. Limit outdoor activity.';
    }
    if (aqi <= 300) {
      return 'Health alert: avoid outdoor activity. Consider wearing a mask outdoors.';
    }
    return 'Health emergency. Stay indoors and keep windows closed.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Air Quality Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Use my location',
            onPressed: () => _loadAirQuality(),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Send test alert',
            onPressed: () => NotificationService.showTestAlert(),
          ),
          if (_geo != null)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'View on map',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapScreen(
                      lat: _geo![0],
                      lon: _geo![1],
                      cityName: _cityName,
                      aqi: _aqi ?? 0,
                      aqiColor: _aqiColor(_aqi ?? 0),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      floatingActionButton: (_aqi != null)
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      aqi: _aqi!,
                      category: _aqiCategory(_aqi!),
                      cityName: _cityName,
                      pollutants: _pollutants,
                    ),
                  ),
                );
              },
              tooltip: 'Ask Assistant',
              child: const Icon(Icons.chat_bubble_outline, size: 28),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: SingleChildScrollView(child: _buildBody())),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search a city (e.g. chennai)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (value) => _loadAirQuality(city: value),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _loadAirQuality(city: _searchController.text),
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 100),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadAirQuality(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final aqi = _aqi ?? 0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_fallbackNotice != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fallbackNotice!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          Text(_cityName,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 80,
            backgroundColor: _aqiColor(aqi),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$aqi',
                    style: const TextStyle(
                        fontSize: 40,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                const Text('AQI', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _aqiCategory(aqi),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _aqiColor(aqi)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _healthAdvice(aqi),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const SizedBox(height: 24),
          if (_pollutants != null) _buildPollutantGrid(),
          const SizedBox(height: 28),
          if (_pm25Forecast != null && _pm25Forecast!.isNotEmpty)
            _buildTrendChart(),
        ],
      ),
    );
  }

  Widget _buildPollutantGrid() {
    final entries = <MapEntry<String, String>>[];
    final labels = {
      'pm25': 'PM2.5',
      'pm10': 'PM10',
      'co': 'CO',
      'no2': 'NO2',
      'o3': 'O3',
      'so2': 'SO2',
    };

    labels.forEach((key, label) {
      if (_pollutants!.containsKey(key)) {
        final value = _pollutants![key]['v'];
        entries.add(MapEntry(label, value.toString()));
      }
    });

    if (entries.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: entries.map((e) {
        return Container(
          width: 90,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Text(e.value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(e.key,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Simple bar chart of PM2.5 daily average, built with plain Flutter
  // widgets (no chart package needed) to keep the dependency footprint small.
  Widget _buildTrendChart() {
    // Sort by date ascending, keep at most the last 7 entries for a clean look
    final data = List<Map<String, dynamic>>.from(_pm25Forecast!);
    data.sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));
    final recent = data.length > 7 ? data.sublist(data.length - 7) : data;

    final maxAvg = recent
        .map((e) => (e['avg'] as num).toDouble())
        .fold<double>(1, (prev, v) => v > prev ? v : prev);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PM2.5 Trend (recent days)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Daily average PM2.5, from WAQI station history/forecast',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: recent.map((entry) {
              final avg = (entry['avg'] as num).toDouble();
              final day = entry['day'] as String; // format: YYYY-MM-DD
              final label = day.length >= 10 ? day.substring(5) : day; // MM-DD
              final barHeight = (avg / maxAvg) * 100;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        avg.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: barHeight.clamp(4, 100),
                        decoration: BoxDecoration(
                          color: _aqiColor(avg.round()),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}