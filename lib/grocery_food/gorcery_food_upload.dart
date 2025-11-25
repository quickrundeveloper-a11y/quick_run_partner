import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class GorceryFoodUpload extends StatefulWidget {
  final String driverAuthId;
  const GorceryFoodUpload({super.key, required this.driverAuthId});

  @override
  State<GorceryFoodUpload> createState() => _GorceryFoodUploadState();
}

class _GorceryFoodUploadState extends State<GorceryFoodUpload> {
  final _formKey = GlobalKey<FormState>();

  // Top-level selections
  String? _type; // 'food' | 'grocery'

  // Grocery path
  String? _groceryEdible; // 'edible' | 'non-edible'
  String? _groceryVegType; // 'veg' | 'non-veg' (only when edible)

  // Food path
  String? _foodVegType; // 'veg' | 'non-veg'

  // Categories (fetched from Firestore)
  List<String> _categories = [];
  String? _selectedCategory;

  // Item name
  final TextEditingController _itemNameCtrl = TextEditingController();
  // Keyword(s)
  final TextEditingController _keywordsCtrl = TextEditingController();

  // Key Information
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _ingredientsCtrl = TextEditingController();
  final TextEditingController _concernCtrl = TextEditingController();
  final TextEditingController _keyIngredientsCtrl = TextEditingController();

  // Info
  final TextEditingController _sellerCtrl = TextEditingController();
  final TextEditingController _returnPolicyCtrl = TextEditingController();
  final TextEditingController _customerCareCtrl = TextEditingController();
  final TextEditingController _shelfLifeCtrl = TextEditingController();
  final TextEditingController _unitNoteCtrl = TextEditingController();

  // Price tiers
  final List<_PriceTier> _priceTiers = [
    _PriceTier(),
  ];

  // Additional food items (name + price)
  final List<_ExtraItem> _extraItems = [];

  // Images
  final List<XFile> _images = [];

  bool _saving = false;

  String? _restaurantId;
  Future<void> _fetchRestaurantIdFromPhone() async {
    final snap = await FirebaseFirestore.instance.collection('Restaurent_shop').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['phone'] == widget.driverAuthId) {
        setState(() {
          _restaurantId = doc.id;
        });
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchRestaurantIdFromPhone();
  }

  @override
  void dispose() {
    _keywordsCtrl.dispose();
    _descriptionCtrl.dispose();
    _ingredientsCtrl.dispose();
    _concernCtrl.dispose();
    _keyIngredientsCtrl.dispose();

    _sellerCtrl.dispose();
    _returnPolicyCtrl.dispose();
    _customerCareCtrl.dispose();
    _shelfLifeCtrl.dispose();
    _unitNoteCtrl.dispose();
    _itemNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories(String type) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('categories')
          .where('type', isEqualTo: type)
          .get();

      if (!mounted) return;

      setState(() {
        _categories = snapshot.docs.map((doc) {
          final data = doc.data();
          return (data['name'] ?? '').toString().trim();
        }).where((name) => name.isNotEmpty).toList();
      });

      if (_categories.isEmpty) {
        _showSnack('No categories found for $type');
      } else {
        _showSnack('Loaded ${_categories.length} categories');
      }
    } catch (e) {
      _showSnack('Error loading categories: $e');
    }
  }

  Future<void> _addCategoryDialog() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Category'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. Beverages / Bakery / Snacks',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add')),
          ],
        );
      },
    );
    if (res != null && res.isNotEmpty && _type != null) {
      // Save to Firestore and refresh
      final name = res;
      await FirebaseFirestore.instance.collection('categories').add({
        'type': _type,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _loadCategories(_type!);
      setState(() => _selectedCategory = name);
    }
  }

  String? _validatePriceOrder() {
    for (int i = 0; i < _priceTiers.length; i++) {
      final t = _priceTiers[i];
      if (t.price == null || t.mrp == null) return 'Fill price and MRP for all tiers';
      if ((t.price ?? 0) >= (t.mrp ?? 0)) return 'Tier ${i + 1}: Price must be less than MRP';
      if (i > 0) {
        final prev = _priceTiers[i - 1];
        if ((t.price ?? 0) <= (prev.price ?? 0)) return 'Tier ${i + 1}: Price must be higher than previous tier';
        if ((t.mrp ?? 0) <= (prev.mrp ?? 0)) return 'Tier ${i + 1}: MRP must be higher than previous tier';
      }
      if (t.unit == 'pieces') {
        if ((t.multiple ?? 0) < 1) return 'Tier ${i + 1}: Multiple must be at least 1 for pieces';
      } else {
        if ((t.quantity ?? 0) <= 0) return 'Tier ${i + 1}: Enter a valid quantity';
      }
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final orderError = _validatePriceOrder();
    if (orderError != null) {
      _showSnack(orderError);
      return;
    }

    setState(() => _saving = true);

    try {
      if (_images.isEmpty) {
        _showSnack('Please add at least one image');
        setState(() => _saving = false);
        return;
      }

      final userId = _restaurantId;
      if (userId == null) {
        _showSnack('Restaurant ID not resolved');
        setState(() => _saving = false);
        return;
      }
      final imageUrls = <String>[];
      final storageRef = FirebaseStorage.instance.ref().child('product_images').child(userId);

      for (final image in _images) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        final uploadTask = storageRef.child(fileName).putFile(File(image.path));
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();
        imageUrls.add(downloadUrl);
      }

      final data = {
        'imageUrls': imageUrls,
        'type': _type, // food | grocery
        'groceryEdible': _type == 'grocery' ? _groceryEdible : null,
        'groceryVegType': _type == 'grocery' && _groceryEdible == 'edible' ? _groceryVegType : null,
        'foodVegType': _type == 'food' ? _foodVegType : null,
        'category': _selectedCategory,
        'name': _itemNameCtrl.text.trim(),
        'keywords': _keywordsCtrl.text.trim(),
        'priceTiers': _priceTiers
            .map((t) => {
                  'price': t.price,
                  'mrp': t.mrp,
                  'unit': t.unit,
                  // if unit is pieces, persist multiple; else persist quantity
                  'quantity': t.unit == 'pieces' ? null : t.quantity,
                  'multiple': t.unit == 'pieces' ? t.multiple : null,
                  'percentOff': t.percentOff,
                })
            .toList(),
        'extraFoodItems': _type == 'food'
            ? _extraItems.map((e) => {'name': e.name, 'price': e.price}).toList()
            : [],
        'keyInformation': {
          'description': _descriptionCtrl.text.trim(),
          'ingredients': _ingredientsCtrl.text.trim(),
          'concern': _concernCtrl.text.trim(),
          'keyIngredients': _keyIngredientsCtrl.text.trim(),
        },
        'info': {
          'seller': _sellerCtrl.text.trim(),
          'returnPolicy': _returnPolicyCtrl.text.trim(),
          'customerCare': _customerCareCtrl.text.trim(),
          'shelfLife': _shelfLifeCtrl.text.trim(),
          'unitNote': _unitNoteCtrl.text.trim(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'restaurentId': userId,
      };

      final collectionName = _type == 'food' ? 'food' : 'grocery';
      await FirebaseFirestore.instance.collection(collectionName).add(data);
      _showSnack('Saved successfully');
      if (mounted) {
        setState(() {
          _resetForm();
        });
      }
    } catch (e) {
      _showSnack('Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _type = null;
    _groceryEdible = null;
    _groceryVegType = null;
    _foodVegType = null;
    _categories = [];
    _selectedCategory = null;
    _keywordsCtrl.clear();
    _descriptionCtrl.clear();
    _ingredientsCtrl.clear();
    _concernCtrl.clear();
    _keyIngredientsCtrl.clear();
    _sellerCtrl.clear();
    _returnPolicyCtrl.clear();
    _customerCareCtrl.clear();
    _shelfLifeCtrl.clear();
    _unitNoteCtrl.clear();
    _itemNameCtrl.clear();
    _priceTiers
      ..clear()
      ..add(_PriceTier());
    _extraItems.clear();
    _images.clear();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-cache icons if needed, or other context-dependent initializations
  }

  Future<void> _pickImages() async {
    final pickedFiles = await ImagePicker().pickMultiImage();
    setState(() => _images.addAll(pickedFiles));
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Add Item')),
      body: Form(
        key: _formKey,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _typeDropdown()),
                  ],
                ),
                const SizedBox(height: 12),
                if (_type == 'grocery') _groceryBlock(),
                if (_type == 'food') _foodBlock(),
                const SizedBox(height: 16),
                _keywordsField(),
                const SizedBox(height: 16),
                _categoryRow(),
                const SizedBox(height: 24),
                _imagePickerSection(),
                const SizedBox(height: 24),
                _priceTiersSection(),
                const SizedBox(height: 24),
                const Text('Key Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _outlinedField(_descriptionCtrl, 'Description', 'Short description of the product'),
                const SizedBox(height: 8),
                _outlinedField(_ingredientsCtrl, 'Ingredients', 'List primary ingredients'),
                const SizedBox(height: 8),
                _outlinedField(_concernCtrl, 'Concern', 'e.g. Allergens, diet info, storage'),
                const SizedBox(height: 8),
                _outlinedField(_keyIngredientsCtrl, 'Key ingredients', 'Highlight key actives or main contents'),
                const SizedBox(height: 24),
                const Text('Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _outlinedField(_sellerCtrl, 'Seller', 'Seller / Brand'),
                const SizedBox(height: 8),
                _outlinedField(_returnPolicyCtrl, 'Return policy', 'e.g. 7 days replacement'),
                const SizedBox(height: 8),
                _outlinedField(_customerCareCtrl, 'Customer care details', 'Phone / Email'),
                const SizedBox(height: 8),
                _outlinedField(_shelfLifeCtrl, 'Shelf life', 'e.g. 6 months from MFG'),
                const SizedBox(height: 8),
                _outlinedField(_unitNoteCtrl, 'Unit', 'Any unit notes (optional)'),
                if (_type == 'food') ...[
                  const SizedBox(height: 24),
                  _extraItemsSection(),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Save to Firestore'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeDropdown() {
    return DropdownButtonFormField<String>(
      value: _type,
      decoration: const InputDecoration(
        labelText: 'Category type',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'food', child: Text('Food')),
        DropdownMenuItem(value: 'grocery', child: Text('Grocery')),
      ],
      onChanged: (v) async {
        setState(() {
          _type = v;
          _groceryEdible = null;
          _groceryVegType = null;
          _foodVegType = null;
          _selectedCategory = null;
          _categories = [];
        });
        if (v != null) await _loadCategories(v);
      },
      validator: (v) => v == null ? 'Select Food or Grocery' : null,
    );
  }

  Widget _groceryBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _groceryEdible,
          decoration: const InputDecoration(
            labelText: 'Grocery type',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'edible', child: Text('Edible item')),
            DropdownMenuItem(value: 'non-edible', child: Text('Non-edible item')),
          ],
          onChanged: (v) => setState(() {
            _groceryEdible = v;
            if (v != 'edible') _groceryVegType = null; // only for edible
          }),
          validator: (v) => v == null ? 'Select edible or non-edible' : null,
        ),
        const SizedBox(height: 12),
        if (_groceryEdible == 'edible')
          DropdownButtonFormField<String>(
            value: _groceryVegType,
            decoration: const InputDecoration(
              labelText: 'Veg/Non-veg',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'veg', child: Text('Veg')),
              DropdownMenuItem(value: 'non-veg', child: Text('Non-veg')),
            ],
            onChanged: (v) => setState(() => _groceryVegType = v),
            validator: (v) => v == null ? 'Select veg or non-veg' : null,
          ),
        const SizedBox(height: 12),
        _nameField(),
      ],
    );
  }

  Widget _foodBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _foodVegType,
          decoration: const InputDecoration(
            labelText: 'Veg/Non-veg (Food)',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'veg', child: Text('Veg')),
            DropdownMenuItem(value: 'non-veg', child: Text('Non-veg')),
          ],
          onChanged: (v) => setState(() => _foodVegType = v),
          validator: (v) => v == null ? 'Select veg or non-veg' : null,
        ),
        const SizedBox(height: 12),
        _nameField(),
      ],
    );
  }

  Widget _nameField() {
    return TextFormField(
      controller: _itemNameCtrl,
      decoration: const InputDecoration(
        labelText: 'Item name',
        hintText: 'e.g. Paneer Tikka / Fortune Atta',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter item name' : null,
    );
  }

  Widget _imagePickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Images', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_images.isEmpty)
          Center(
            child: OutlinedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add Images'),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length + 1,
              itemBuilder: (context, index) {
                if (index == _images.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Center(
                      child: IconButton.filled(
                        iconSize: 32,
                        onPressed: _pickImages,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        tooltip: 'Add more images',
                      ),
                    ),
                  );
                }
                final imageFile = _images[index];
                return Container(
                  width: 120,
                  height: 120,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(imageFile.path), fit: BoxFit.cover)),
                      Positioned(top: 0, right: 0, child: _imageDeleteButton(index)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _keywordsField() {
    return TextFormField(
      controller: _keywordsCtrl,
      decoration: const InputDecoration(
        labelText: 'Keywords',
        hintText: 'e.g. spicy, sugar-free, organic',
        border: OutlineInputBorder(),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter at least one keyword' : null,
    );
  }

  Widget _categoryRow() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: [
              ..._categories.map((categoryName) => DropdownMenuItem(
                    value: categoryName,
                    child: Text(categoryName, overflow: TextOverflow.ellipsis),
                  )),
              const DropdownMenuItem(
                value: '__add_new__',
                child: Text('➕ Add new', style: TextStyle(color: Colors.blue)),
              ),
            ],
            onChanged: (v) async {
              if (v == '__add_new__') {
                await _addCategoryDialog();
              } else {
                setState(() => _selectedCategory = v);
              }
            },
            validator: (v) => v == null ? 'Choose or add a category' : null,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _addCategoryDialog,
          tooltip: 'Add category',
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _imageDeleteButton(int index) {
    return InkWell(
      onTap: () => setState(() => _images.removeAt(index)),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _priceTiersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pricing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._priceTiers.asMap().entries.map((entry) {
          final index = entry.key;
          final tier = entry.value;
          return _priceTierCard(index, tier);
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                final err = _validatePriceOrder();
                if (err != null && _priceTiers.length > 1) {
                  _showSnack(err);
                  return;
                }
                setState(() => _priceTiers.add(_PriceTier()));
              },
              icon: const Icon(Icons.add),
              label: const Text('Add price tier'),
            ),
            const SizedBox(width: 12),
            if (_priceTiers.length > 1)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _priceTiers.removeLast());
                },
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Remove last'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _priceTierCard(int index, _PriceTier tier) {
    final percent = tier.percentOff;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tier ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (percent != null) Chip(label: Text('${percent.toStringAsFixed(1)}% off')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'MRP', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => tier.mrp = double.tryParse(v)),
                    validator: (v) {
                      final x = double.tryParse(v ?? '');
                      if (x == null || x <= 0) return 'Enter valid MRP';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => tier.price = double.tryParse(v)),
                    validator: (v) {
                      final p = double.tryParse(v ?? '');
                      final m = tier.mrp;
                      if (p == null || p <= 0) return 'Enter valid price';
                      if (m != null && p >= m) return 'Price < MRP';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: tier.unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pieces', child: Text('Pieces')),
                      DropdownMenuItem(value: 'gram', child: Text('Gram')),
                      DropdownMenuItem(value: 'kilogram', child: Text('Kilogram')),
                      DropdownMenuItem(value: 'litre', child: Text('Litre')),
                      DropdownMenuItem(value: 'millimeter', child: Text('Millimeter')),
                      DropdownMenuItem(value: 'centimeter', child: Text('Centimeter')),
                      DropdownMenuItem(value: 'meter', child: Text('Meter')),
                    ],
                    onChanged: (v) => setState(() {
                      tier.unit = v;
                      // Clear the other field when switching unit type
                      if (tier.unit == 'pieces') {
                        tier.quantity = null;
                      } else {
                        tier.multiple = null;
                      }
                    }),
                    validator: (v) => v == null ? 'Select unit' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tier.unit == 'pieces') ...[
              TextFormField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Multiple',
                  hintText: 'e.g., 2 (2 pieces), 3 (3 pieces)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => tier.multiple = int.tryParse(v)),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Enter a valid multiple' : null,
              ),
            ] else if (tier.unit != null) ...[
              TextFormField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  hintText: tier.unit == 'litre'
                      ? 'e.g., 0.5 (for 0.5 litre)'
                      : (tier.unit == 'gram' || tier.unit == 'kilogram'
                          ? 'e.g., 500 (grams) or 1 (kilogram)'
                          : 'Enter ${tier.unit} value'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => tier.quantity = double.tryParse(v)),
                validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter quantity' : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _extraItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Additional Food Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._extraItems.asMap().entries.map((e) => _extraItemTile(e.key, e.value)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _extraItems.add(_ExtraItem())),
          icon: const Icon(Icons.add),
          label: const Text('Add additional item'),
        )
      ],
    );
  }

  Widget _extraItemTile(int index, _ExtraItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    onChanged: (v) => item.name = v.trim(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price', border: OutlineInputBorder()),
                    onChanged: (v) => item.price = double.tryParse(v),
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter price' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _extraItems.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlinedField(TextEditingController ctrl, String label, String hint) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      maxLines: null,
    );
  }
}


class _PriceTier {
  double? price;
  double? mrp;
  String? unit; // pieces | gram | kilogram | litre | millimeter | centimeter | meter
  double? quantity; // used for all units except 'pieces'
  int? multiple; // used when unit == 'pieces'

  double? get percentOff {
    if (price == null || mrp == null || mrp == 0) return null;
    return ((mrp! - price!) / mrp!) * 100;
  }
}

class _ExtraItem {
  String name = '';
  double? price;
}
