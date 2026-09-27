import 'models.dart';

const _alfAdd = [
  Addon('Mayonnaise', 30),
  Addon('Salad Extra', 40),
  Addon('Garlic Sauce', 30),
  Addon('Kuboos (2 pcs)', 20),
  Addon('French Fries', 90),
];
const _pzAdd = [Addon('Extra Cheese', 60), Addon('Jalapeño', 40), Addon('Olives', 40), Addon('Cheese Burst', 90)];
const _bgAdd = [Addon('Extra Patty', 90), Addon('Cheese Slice', 30), Addon('Fried Egg', 30)];
List<Variant> _pz(double b) => [Variant('Regular 8"', b), Variant('Medium 10"', b + 150), Variant('Large 12"', b + 300)];

final seedMenu = <MenuItem>[
  const MenuItem(id: 'g1', code: '101', cat: 'Grill', name: 'Chicken Alfahm Peri Peri', price: 180, bestseller: true,
      desc: 'Charcoal-grilled chicken in fiery peri peri marinade.',
      variants: [Variant('Quarter', 180), Variant('Half', 340), Variant('Full', 640)], addons: _alfAdd),
  const MenuItem(id: 'g2', code: '102', cat: 'Grill', name: 'Chicken Alfahm Classic', price: 170,
      desc: 'Classic Arabic spiced chicken, slow grilled on charcoal.',
      variants: [Variant('Quarter', 170), Variant('Half', 320), Variant('Full', 610)], addons: _alfAdd),
  const MenuItem(id: 'g3', code: '103', cat: 'Grill', name: 'Shawaya Chicken', price: 190,
      desc: 'Rotisserie chicken with garlic and lemon.',
      variants: [Variant('Half', 190), Variant('Full', 360)], addons: _alfAdd),
  const MenuItem(id: 's1', code: '201', cat: 'Starters', name: 'Crispy Calamari', price: 360, desc: 'Lemon aioli, chilli salt'),
  const MenuItem(id: 's2', code: '202', cat: 'Starters', name: 'Loaded Nachos', price: 260, veg: true, bestseller: true, desc: 'Cheese, jalapeño, salsa'),
  const MenuItem(id: 's3', code: '203', cat: 'Starters', name: 'Chicken Wings', price: 340, desc: 'Buffalo or BBQ, 8 pcs'),
  const MenuItem(id: 's4', code: '204', cat: 'Starters', name: 'Tomato Soup', price: 160, veg: true, desc: 'Basil, cream, croutons'),
  const MenuItem(id: 'm1', code: '301', cat: 'Mains', name: 'Butter Chicken', price: 380, bestseller: true, desc: 'Tandoori chicken in rich tomato-butter gravy.'),
  const MenuItem(id: 'm2', code: '302', cat: 'Mains', name: 'Grilled Salmon', price: 890, desc: 'Atlantic salmon, herb butter, greens.'),
  const MenuItem(id: 'm3', code: '303', cat: 'Mains', name: 'Paneer Tikka Masala', price: 340, veg: true, desc: 'Cottage cheese tikka in spiced masala.'),
  const MenuItem(id: 'm4', code: '304', cat: 'Mains', name: 'Mushroom Risotto', price: 420, veg: true, desc: 'Parmesan, truffle oil'),
  MenuItem(id: 'p1', code: '401', cat: 'Pizza', name: 'Margherita', price: 350, veg: true, desc: 'Tomato, mozzarella, fresh basil.', variants: _pz(350), addons: _pzAdd),
  MenuItem(id: 'p2', code: '402', cat: 'Pizza', name: 'Pepperoni', price: 420, desc: 'Double pepperoni', variants: _pz(420), addons: _pzAdd),
  MenuItem(id: 'p3', code: '403', cat: 'Pizza', name: 'Veggie Supreme', price: 390, veg: true, desc: 'Peppers, olives, onion', variants: _pz(390), addons: _pzAdd),
  const MenuItem(id: 'b1', code: '501', cat: 'Burgers', name: 'Classic Smash', price: 320, bestseller: true, desc: 'Double smashed patty, cheddar, pickles.', addons: _bgAdd),
  const MenuItem(id: 'b2', code: '502', cat: 'Burgers', name: 'Crispy Chicken', price: 290, desc: 'Slaw, sriracha mayo', addons: _bgAdd),
  const MenuItem(id: 'b3', code: '503', cat: 'Burgers', name: 'Bean Burger', price: 260, veg: true, desc: 'Avocado, chipotle'),
  const MenuItem(id: 'd1', code: '601', cat: 'Desserts', name: 'Chocolate Lava Cake', price: 240, veg: true, desc: 'Warm dark chocolate fondant.'),
  const MenuItem(id: 'd2', code: '602', cat: 'Desserts', name: 'Tiramisu', price: 280, veg: true, desc: 'Espresso, mascarpone'),
  const MenuItem(id: 'v1', code: '701', cat: 'Beverages', name: 'Fresh Lime Soda', price: 90, veg: true, desc: 'Sweet or salted'),
  const MenuItem(id: 'v2', code: '702', cat: 'Beverages', name: 'Mango Lassi', price: 120, veg: true, bestseller: true, desc: 'Yogurt, Alphonso mango, cardamom.'),
  const MenuItem(id: 'v3', code: '703', cat: 'Beverages', name: 'Cold Brew', price: 180, veg: true, desc: 'Slow-steeped for 18 hours.',
      variants: [Variant('Regular', 180), Variant('Large', 230)], addons: [Addon('Oat Milk', 40), Addon('Extra Shot', 50)]),
  const MenuItem(id: 'v4', code: '704', cat: 'Beverages', name: 'Soft Drink', price: 60, veg: true, desc: 'Coke, Sprite, Fanta'),
];

List<TableModel> seedTables() => [
      TableModel('T1', 'Main hall', 4),
      TableModel('T2', 'Main hall', 4),
      TableModel('T3', 'Main hall', 4),
      TableModel('T4', 'Main hall', 4),
      TableModel('T5', 'Main hall', 4),
      TableModel('T6', 'Main hall', 8, h: 2, reservedFor: '7:30 PM'),
      TableModel('T7', 'Main hall', 4),
      TableModel('T8', 'Main hall', 12, w: 2),
      TableModel('P1', 'Patio', 2),
      TableModel('P2', 'Patio', 4),
      TableModel('P3', 'Patio', 4, reservedFor: '8:00 PM'),
      TableModel('P4', 'Patio', 6, w: 2),
      TableModel('R1', 'Rooftop', 8, w: 2),
      TableModel('R2', 'Rooftop', 4, reservedFor: '9:00 PM'),
    ];

List<PosPrinter> seedPrinters() => [
      PosPrinter(id: 'pr1', name: 'Counter (TM-T82)', conn: PrinterConn.lan, station: 'Counter', forBill: true, ip: '192.168.1.50'),
      PosPrinter(id: 'pr2', name: 'Kitchen (TM-T82)', conn: PrinterConn.lan, station: 'Kitchen', forKot: true, ip: '192.168.1.51'),
    ];
