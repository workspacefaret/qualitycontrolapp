import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';

class NetworkModeService {
  Future<bool> shouldUseOfflineMode() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      final hasNoConnection =
          connectivityResult == ConnectivityResult.none ||
          connectivityResult.toString().contains('none');

      if (hasNoConnection) {
        return true;
      }

      final healthUrl = Uri.parse('${ApiClient.baseUrl}/health');

      final response = await http
          .get(
            healthUrl,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return false;
      }

      return true;
    } catch (error) {
      return true;
    }
  }
}
