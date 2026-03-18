// ignore_for_file: avoid_print, unused_element

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:json_editor_flutter/json_editor_flutter.dart';
import 'package:komodo_defi_framework_example/models/postman_collection_types.dart';
import 'package:komodo_defi_framework_example/services/secure_storage_service.dart';

/// History service that can be used across the app to access request history
class RequestHistoryService {
  static final List<Map<String, dynamic>> _history = [];
  static const String _historyStorageKey = 'request_history';

  /// Get the current history list
  static List<Map<String, dynamic>> get history => _history;

  /// Add a new item to history and save it
  static Future<void> addToHistory(
    Map<String, dynamic> request,
    String response,
  ) async {
    _history.add({
      'request': request,
      'response': response,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _saveHistory();
  }

  /// Load history from storage
  static Future<void> loadHistory() async {
    try {
      final secureStorage = SecureStorageService();
      String? historyString = await secureStorage.read(key: _historyStorageKey);
      if (historyString != null) {
        _history.clear();
        _history.addAll(
          List<Map<String, dynamic>>.from(json.decode(historyString)),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load history: $e');
      }
    }
  }

  /// Save history to storage
  static Future<void> _saveHistory() async {
    try {
      final secureStorage = SecureStorageService();
      await secureStorage.write(
        key: _historyStorageKey,
        value: json.encode(_history),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save history: $e');
      }
    }
  }

  /// Show the history screen
  static void showHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const RequestHistoryScreen()),
    );
  }
}

class RequestPlayground extends StatefulWidget {
  final Future<String> Function(Map<String, dynamic> payload) executeRequest;

  const RequestPlayground({super.key, required this.executeRequest});

  @override
  State<RequestPlayground> createState() => _RequestPlaygroundState();
}

class _RequestPlaygroundState extends State<RequestPlayground> {
  // Static variables for caching the collection data across instances
  static Collection? _collection;
  static String? _rawCollectionData;
  static final List<CollectionItem> _requests = [];

  final TextEditingController _searchController = TextEditingController();
  List<CollectionItem> _filteredRequests = [];
  int _selectedRequestIndex = 0;
  Map<String, dynamic> _jsonData = {};
  String _response = '{}';
  bool _isLoading = false;
  bool _isSending = false;

  String get _responseJson =>
      isValidJson(_response) ? _response : jsonEncode({'response': _response});

  bool isValidJson(String str) {
    try {
      jsonDecode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_requests.isEmpty) {
      _isLoading = true;
      _loadCollection();
    }
    _searchController.addListener(_filterRequests);
    _filteredRequests = _requests;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterRequests() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredRequests =
          _requests
              .where((request) => request.name.toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _loadCollection() async {
    setState(() => _isLoading = true);
    try {
      // If we already have cached collection data, use it
      if (_rawCollectionData != null) {
        if (kDebugMode) {
          print('Using cached Postman collection data from session');
        }
        _parseAndSetupCollection(_rawCollectionData!);
        setState(() => _isLoading = false);
        return;
      }

      final defaultBundle = DefaultAssetBundle.of(context);
      final secureStorage = SecureStorageService();
      String? storedConfig = await secureStorage.read(key: 'postman_config');
      String jsonString;

      if (storedConfig != null) {
        // Use stored configuration if available
        jsonString = storedConfig;
        if (kDebugMode) {
          print('Using stored Postman collection configuration');
        }
      } else {
        // Try to download from GitHub first
        try {
          if (kDebugMode) {
            print('Attempting to download Postman collection from GitHub...');
          }
          final response = await http
              .get(
                Uri.parse(
                  'https://raw.githubusercontent.com/GLEECBTC/komodo-docs-mdx/refs/heads/dev/postman/collections/komodo_defi.postman_collection.json',
                ),
              )
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            jsonString = response.body;
            if (kDebugMode) {
              print('Successfully downloaded Postman collection from GitHub');
            }

            // Save the downloaded collection to secure storage
            await secureStorage.write(key: 'postman_config', value: jsonString);
          } else {
            throw HttpException(
              'Failed to download: HTTP ${response.statusCode}',
            );
          }
        } catch (e) {
          // Fallback to local asset if download fails
          if (kDebugMode) {
            print('Failed to download Postman collection: $e');
            print('Falling back to local asset');
          }
          jsonString = await defaultBundle.loadString(
            'assets/komodo_defi.postman_collection.json',
          );
          if (kDebugMode) {
            print('Loaded local Postman collection');
          }
        }
      }

      // Cache the raw collection data for future uses
      _rawCollectionData = jsonString;
      _parseAndSetupCollection(jsonString);
    } catch (e) {
      if (kDebugMode) {
        print('Error loading collection: $e');
      }
      _showErrorDialog('Failed to load collection: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _parseAndSetupCollection(String jsonString) {
    _collection = Collection.fromJson(
      parseJsonWithCommentStripping(jsonString),
    );

    // Clear the existing requests first to avoid duplicates when reloading
    _requests.clear();
    _extractRequests(_collection!.item);

    if (_requests.isNotEmpty) {
      _selectRequest(0);
    } else {
      if (kDebugMode) {
        print('Warning: No requests found in the collection');
      }
    }
  }

  String stripJsonComments(String input) {
    RegExp regex = RegExp(
      r'\\"|"(?:\\"|[^"])*"|(//.*|/\*[\s\S]*?\*/)',
      multiLine: true,
    );

    return input.replaceAllMapped(regex, (match) {
      if (match.group(1) == null) {
        // This is a string literal, keep it as is
        return match.group(0)!;
      } else {
        // This is a comment, remove it
        return '';
      }
    });
  }

  dynamic parseJsonWithCommentStripping(String jsonString) {
    String strippedJson = stripJsonComments(jsonString);
    return json.decode(strippedJson);
  }

  void _extractRequests(List<CollectionItem> items) {
    for (var item in items) {
      if (item.item != null) {
        _extractRequests(item.item!);
      } else if (item.request != null) {
        _requests.add(item);
      }
    }
  }

  void _selectRequest(int index) {
    if (index < 0 || index >= _requests.length) {
      if (kDebugMode) {
        print('Invalid request index: $index');
      }
      return;
    }

    setState(() {
      _selectedRequestIndex = index;
      String rawBody = _requests[index].request?.body?.raw ?? '{}';
      try {
        _jsonData = parseJsonWithCommentStripping(rawBody);

        // If userpass is set to a masked value, replace it with the placeholder
        if (_jsonData.containsKey('userpass') &&
            (_jsonData['userpass'] == '********' ||
                _jsonData['userpass'] == '')) {
          _jsonData['userpass'] = '{{userpass}}';
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            'Error parsing JSON for request: ${_requests[index].name} - $e',
          );
        }
        _jsonData = {};
      }
      if (kDebugMode) {
        print('Selected request: ${_requests[index].name}');
      }
      _response = '{}';
    });
  }

  Future<void> _executeRequest() async {
    setState(() => _isSending = true);
    try {
      String response = await widget.executeRequest(_jsonData);
      setState(() {
        _response = response;
      });
      // Add to history via the service
      await RequestHistoryService.addToHistory(_jsonData, response);
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
      // _showErrorDialog('Failed to execute request: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading Postman Collection...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search collection...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredRequests.length,
                        itemBuilder: (context, index) {
                          final request = _filteredRequests[index];
                          return ListTile(
                            title: Text(request.name),
                            selected:
                                _requests.indexOf(request) ==
                                _selectedRequestIndex,
                            onTap:
                                () =>
                                    _selectRequest(_requests.indexOf(request)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: JsonEditor(
                        key: Key(_selectedRequestIndex.toString()),
                        json: jsonEncode(_jsonData),
                        onChanged: (value) {
                          setState(() {
                            _jsonData =
                                value is String ? jsonDecode(value) : value;
                          });
                        },
                        themeColor: Colors.blue,
                        enableHorizontalScroll: true,
                        actions: [
                          IconButton(
                            color: Theme.of(context).colorScheme.onPrimary,
                            icon: Icon(Icons.send),
                            onPressed: _isSending ? null : _executeRequest,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Response:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      key: ValueKey(_responseJson),
                      child: JsonEditor(
                        editors:
                            isValidJson(_response)
                                ? Editors.values
                                : [Editors.text, Editors.tree],
                        json: _responseJson,
                        enableKeyEdit: false,
                        enableValueEdit: false,
                        themeColor: Colors.green,
                        onChanged: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget that displays request history after loading it
class RequestHistoryScreen extends StatefulWidget {
  const RequestHistoryScreen({super.key});

  @override
  State<RequestHistoryScreen> createState() => _RequestHistoryScreenState();
}

class _RequestHistoryScreenState extends State<RequestHistoryScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    await RequestHistoryService.loadHistory();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Request History')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RequestHistoryList(history: RequestHistoryService.history),
    );
  }
}

/// Widget that displays the history items list
class RequestHistoryList extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const RequestHistoryList({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(child: Text('No request history available'));
    }

    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[history.length - 1 - index];
        return ListTile(
          title: Text('Request ${history.length - index}'),
          subtitle: Text(item['timestamp']),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => HistoryDetailScreen(item: item),
              ),
            );
          },
        );
      },
    );
  }
}

/// Screen that shows the details of a history item
class HistoryDetailScreen extends StatelessWidget {
  final Map<String, dynamic> item;

  const HistoryDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Details')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Request:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                const JsonEncoder.withIndent('  ').convert(item['request']),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Response:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Card(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                child: Text(item['response']),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
