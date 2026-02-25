
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum StockFilter { all, highToLow, lowToHigh, outOfStock }

class SellerStock extends StatefulWidget {
  final String driverAuthId;
  const SellerStock(this.driverAuthId, {super.key});

  @override
  State<SellerStock> createState() => _SellerStockState();
}

class _SellerStockState extends State<SellerStock> {
  String? _currentRestaurantId;
  List<DocumentSnapshot> _items = [];
  List<DocumentSnapshot> _filteredItems = [];
  Map<String, int> _itemQty = {};
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  StockFilter _activeFilter = StockFilter.all;

  @override
  void initState() {
    super.initState();
    _fetchRestaurantId();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200 &&
          _hasMore &&
          !_isLoading &&
          !_isSearching) {
        _loadMoreProducts();
      }
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchRestaurantId() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Restaurent_shop')
          .where('phone', isEqualTo: widget.driverAuthId)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        setState(() {
          _currentRestaurantId = snap.docs.first.id;
        });
        _loadProducts();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load restaurant: $e');
    }
  }

  Future<void> _loadProducts() async {
    if (_currentRestaurantId == null || _isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      // Load grocery items
      Query groceryQuery = FirebaseFirestore.instance
          .collection('grocery')
          .where('restaurentId', isEqualTo: _currentRestaurantId)
          .limit(15);

      // Load food items
      Query foodQuery = FirebaseFirestore.instance
          .collection('food')
          .where('restaurentId', isEqualTo: _currentRestaurantId)
          .limit(15);

      if (_lastDoc != null) {
        groceryQuery = groceryQuery.startAfterDocument(_lastDoc!);
        foodQuery = foodQuery.startAfterDocument(_lastDoc!);
      }

      final grocerySnap = await groceryQuery.get();
      final foodSnap = await foodQuery.get();

      List<DocumentSnapshot> combined = [...grocerySnap.docs, ...foodSnap.docs];

      if (combined.isEmpty) {
        setState(() => _hasMore = false);
      } else {
        _lastDoc = combined.last;
        setState(() {
          _items.addAll(combined);
          _filteredItems = List.from(_items);
          for (final doc in combined) {
            _initializeItemQuantity(doc);
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load products: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _initializeItemQuantity(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      final existing = (data != null && data['stockQty'] != null)
          ? int.tryParse(data['stockQty'].toString()) ?? 0
          : 0;
      _itemQty[doc.id] = existing;
    } catch (_) {
      _itemQty[doc.id] = _itemQty[doc.id] ?? 0;
    }
  }

  Future<void> _loadMoreProducts() async {
    await _loadProducts();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();

    if (query.isEmpty) {
      setState(() {
        _filteredItems = List.from(_items);
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final filtered = _items.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final name = (data != null && data.containsKey('name'))
          ? data['name'].toString().toLowerCase()
          : '';
      return name.contains(query);
    }).toList();

    _filteredItems = filtered;
    _applyFilter();
  }

  void _applyFilter() {
    List<DocumentSnapshot> list = List.from(_filteredItems);

    if (_activeFilter == StockFilter.outOfStock) {
      list = list.where((doc) {
        final qty = _itemQty[doc.id] ?? 0;
        return qty == 0;
      }).toList();
    }

    if (_activeFilter == StockFilter.highToLow) {
      list.sort((a, b) => (_itemQty[b.id] ?? 0).compareTo(_itemQty[a.id] ?? 0));
    }

    if (_activeFilter == StockFilter.lowToHigh) {
      list.sort((a, b) => (_itemQty[a.id] ?? 0).compareTo(_itemQty[b.id] ?? 0));
    }

    setState(() {
      _filteredItems = list;
    });
  }

  Future<void> _updateStockQuantity(String docId, String collectionName, int newQty) async {
    try {
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(docId)
          .update({'stockQty': newQty});
    } catch (e) {
      throw Exception('Failed to update: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }



  Widget _buildQuantityControls(DocumentSnapshot doc, int currentQty) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.remove, color: currentQty == 0 ? Colors.grey : Colors.red),
            onPressed: currentQty == 0 ? null : () => _adjustQuantity(doc, -1),
            splashRadius: 20,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              currentQty.toString(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.green),
            onPressed: () => _adjustQuantity(doc, 1),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Future<void> _adjustQuantity(DocumentSnapshot doc, int change) async {
    final docId = doc.id;
    final collectionName = doc.reference.parent.id;
    final current = _itemQty[docId] ?? 0;
    final newQty = current + change;

    if (newQty < 0) return;

    final oldValue = current; // Store old value for rollback
    setState(() => _itemQty[docId] = newQty);

    try {
      await _updateStockQuantity(docId, collectionName, newQty);
      if (change > 0) {
      } else {
      }
    } catch (e) {
      // Rollback on error
      setState(() => _itemQty[docId] = oldValue);
      _showErrorSnackBar('Failed to update quantity');
    }
  }

  Widget _buildProductItem(int index) {
    final doc = _filteredItems[index];
    final data = doc.data() as Map<String, dynamic>?;

    final name = (data != null && data.containsKey('name'))
        ? data['name']?.toString() ?? 'Unnamed Item'
        : 'Unnamed Item';

    final imageList = (data != null && data['imageUrls'] is List)
        ? (data['imageUrls'] as List)
        : [];
    final imageUrl = imageList.isNotEmpty ? imageList.first : null;

    final vegTypeRaw = (data != null && data.containsKey('foodVegType'))
        ? data['foodVegType']
        : (data != null && data.containsKey('groceryVegType')
        ? data['groceryVegType']
        : null);
    final vegType = vegTypeRaw?.toString() ?? 'N/A';

    final tierList = (data != null && data['priceTiers'] is List)
        ? (data['priceTiers'] as List)
        : [];
    final priceTier = tierList.isNotEmpty ? tierList.first : null;

    final price = (priceTier != null && priceTier['price'] != null)
        ? '₹${priceTier['price']}'
        : 'N/A';
    final mrp = (priceTier != null && priceTier['mrp'] != null)
        ? '₹${priceTier['mrp']}'
        : '';
    final quantity = (priceTier != null && priceTier['quantity'] != null)
        ? priceTier['quantity'].toString()
        : '';
    final unit = (priceTier != null && priceTier['unit'] != null)
        ? priceTier['unit'].toString()
        : '';

    final currentQty = _itemQty[doc.id] ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: imageUrl != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.shopping_bag, color: Colors.grey),
                ),
              )
                  : const Icon(Icons.shopping_bag, color: Colors.grey),
            ),
            const SizedBox(width: 12),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getVegTypeColor(vegType),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          vegType,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (mrp.isNotEmpty && mrp != 'N/A')
                        Text(
                          mrp,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),

                  if (quantity.isNotEmpty && unit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$quantity $unit',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Quantity Controls
            _buildQuantityControls(doc, currentQty),
          ],
        ),
      ),
    );
  }

  Color _getVegTypeColor(String vegType) {
    switch (vegType.toLowerCase()) {
      case 'veg':
        return Colors.green;
      case 'non-veg':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget _buildSearchBar() {
    Widget tab(String text, StockFilter filter) {
      final bool active = _activeFilter == filter;
      return GestureDetector(
        onTap: () {
          setState(() {
            _activeFilter = filter;
            _applyFilter();
          });
        },
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: active ? Colors.white : Colors.black,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: const InputDecoration(
                hintText: 'Search products...',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.grey),
              onPressed: () {
                _searchController.clear();
                _searchFocusNode.unfocus();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    Widget tab(String text, StockFilter filter) {
      final bool active = _activeFilter == filter;
      return GestureDetector(
        onTap: () {
          setState(() {
            _activeFilter = filter;
            _applyFilter();
          });
        },
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: active ? Colors.white : Colors.black,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          tab('All', StockFilter.all),
          tab('Sort: High → Low', StockFilter.highToLow),
          tab('Sort: Low → High', StockFilter.lowToHigh),
          tab('Out of Stock', StockFilter.outOfStock),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          Text(
            _isSearching ? 'No products found' : 'No products available',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isSearching
                ? 'Try a different search term'
                : 'Add products to your inventory',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return _isLoading
        ? const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      ),
    )
        : _hasMore && !_isSearching
        ? Container(
      padding: const EdgeInsets.all(20),
      child: const Center(
        child: Text(
          'Scroll to load more',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    )
        : Container(
      padding: const EdgeInsets.all(20),
      child: const Center(
        child: Text(
          'No more products',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Stock Management',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(),
          _buildFilterTabs(),

          // Product List
          Expanded(
            child: _currentRestaurantId == null
                ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            )
                : _filteredItems.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _items.clear();
                  _filteredItems.clear();
                  _itemQty.clear();
                  _lastDoc = null;
                  _hasMore = true;
                });
                await _loadProducts();
              },
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _filteredItems.length + 1,
                itemBuilder: (context, index) {
                  if (index < _filteredItems.length) {
                    return _buildProductItem(index);
                  } else {
                    return _buildLoadingIndicator();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}



