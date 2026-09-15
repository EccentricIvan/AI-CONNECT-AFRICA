import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ai_model_manager.dart';
import '../../shared/coding/code_lab.dart';
import '../../shared/coding/code_lab_session.dart';

/// App Dev Lab: guided lessons → edit the code → RUN → the real page.
///
/// Same architecture as the Web Dev Lab, on the same [CodeLabScaffold]. The
/// coding model no longer builds the app: the student writes the code and a
/// browser engine paints exactly that code, so the preview always appears
/// instantly and always matches the editor. Autocorrect is the only route to
/// the model, and it is an explicit, optional step.
class AppDevLabScreen extends ConsumerStatefulWidget {
  const AppDevLabScreen({super.key});

  @override
  ConsumerState<AppDevLabScreen> createState() => _AppDevLabScreenState();
}

class _AppDevLabScreenState extends ConsumerState<AppDevLabScreen> {
  @override
  void initState() {
    super.initState();
    // Autocorrect still reaches the coder; nothing else on this screen does.
    scheduleLiteRtMode(ActiveModelMode.appCoder);
  }

  @override
  Widget build(BuildContext context) {
    return const CodeLabScaffold(
      title: 'App Dev Lab',
      icon: Icons.phone_android,
      lessons: appLabLessons,
      sessionId: CodeLabSections.app,
      editorHint: 'Build your app screen here — HTML, CSS and JavaScript...',
    );
  }
}

// ── Lessons ──────────────────────────────────────────────────────────────────

/// Every starter is a complete document with a charset, phone-width, and no
/// network reference — it has to render on a plane, on a bus, in a village
/// with no signal, on both Android and Windows.
///
/// Data is kept in plain JavaScript variables rather than `localStorage`: the
/// Android preview loads pages on an `about:blank` origin, where storage
/// throws, so a storage lesson would fail on one platform and not the other.
const appLabLessons = <CodeLabLesson>[
  CodeLabLesson(
    title: 'Lesson 1: Your First App Screen',
    instruction:
        'Every app screen has a bar at the top with a title, and content below '
        'it. This is the whole shape of an app. Change the app name and the '
        'welcome text, then tap RUN.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #2563eb; color: white; padding: 16px; font-size: 18px;
              font-weight: 700; }
    .content { padding: 16px; }
  </style>
</head>
<body>

  <div class="topbar">My First App</div>
  <div class="content">
    <h2>Welcome!</h2>
    <p>This is my app screen.</p>
  </div>

</body>
</html>''',
    hint: 'Change #2563eb to #16a34a to make the top bar green.',
    challenge: 'Add a second paragraph telling the user what your app does.',
  ),
  CodeLabLesson(
    title: 'Lesson 2: Cards Hold Your Content',
    instruction:
        'Apps group information into cards — a white box with rounded corners '
        'and a soft shadow. Cards are what make a screen look like an app '
        'instead of a document. Try adding a third card.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .content { padding: 16px; }
    .card { background: white; border-radius: 12px; padding: 16px;
            margin-bottom: 12px; box-shadow: 0 2px 6px rgba(0,0,0,0.08); }
    .card h3 { margin: 0 0 6px 0; }
    .card p { margin: 0; color: #64748b; font-size: 14px; }
  </style>
</head>
<body>

  <div class="topbar">My Notes</div>
  <div class="content">
    <div class="card">
      <h3>Maths homework</h3>
      <p>Finish questions 1 to 10.</p>
    </div>
    <div class="card">
      <h3>Science project</h3>
      <p>Bring a plant for the experiment.</p>
    </div>
  </div>

</body>
</html>''',
    hint: 'Copy one whole <div class="card">…</div> block and change the text.',
    challenge: 'Give one card a coloured left border using border-left.',
  ),
  CodeLabLesson(
    title: 'Lesson 3: A List of Items',
    instruction:
        'Most apps are a list of things — messages, tasks, products, students. '
        'A list is rows stacked on top of each other, each with a line under '
        'it. Add two more rows to the list.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: white; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .row { padding: 14px 16px; border-bottom: 1px solid #e5e7eb;
           display: flex; justify-content: space-between; }
    .name { font-weight: 600; }
    .price { color: #16a34a; font-weight: 700; }
  </style>
</head>
<body>

  <div class="topbar">Market Prices</div>

  <div class="row"><span class="name">Maize (1 kg)</span><span class="price">2,500</span></div>
  <div class="row"><span class="name">Beans (1 kg)</span><span class="price">4,000</span></div>
  <div class="row"><span class="name">Rice (1 kg)</span><span class="price">5,200</span></div>

</body>
</html>''',
    hint: 'Copy a whole <div class="row">…</div> line and change the two values.',
    challenge: 'Make the prices red instead of green by changing the colour.',
  ),
  CodeLabLesson(
    title: 'Lesson 4: A Button That Does Something',
    instruction:
        'An app reacts when you tap it. addEventListener listens for a tap, '
        'then runs your code. Here the button changes the counter. Tap RUN, '
        'then tap the button in the preview.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8;
           text-align: center; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; text-align: left; }
    .count { font-size: 64px; font-weight: 800; margin: 40px 0 20px; }
    button { background: #2563eb; color: white; border: none; padding: 14px 28px;
             border-radius: 10px; font-size: 16px; font-weight: 600; }
  </style>
</head>
<body>

  <div class="topbar">Counter App</div>
  <div class="count" id="count">0</div>
  <button id="addBtn">Add one</button>

  <script>
    let count = 0;
    const label = document.getElementById('count');

    document.getElementById('addBtn').addEventListener('click', () => {
      count = count + 1;
      label.textContent = count;
    });
  </script>

</body>
</html>''',
    hint: 'Change count + 1 to count + 5 to jump by five each tap.',
    challenge: 'Add a second button that takes one away.',
  ),
  CodeLabLesson(
    title: 'Lesson 5: Taking Input From the User',
    instruction:
        'Real apps let people type. Read what they typed with .value, then do '
        'something with it. Type your name in the preview and tap the button.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .content { padding: 16px; }
    input { width: 100%; padding: 12px; border: 1px solid #cbd5e1;
            border-radius: 8px; font-size: 15px; box-sizing: border-box; }
    button { width: 100%; margin-top: 10px; background: #2563eb; color: white;
             border: none; padding: 13px; border-radius: 8px; font-size: 15px;
             font-weight: 600; }
    .greeting { margin-top: 18px; font-size: 18px; font-weight: 700;
                color: #2563eb; }
  </style>
</head>
<body>

  <div class="topbar">Greeting App</div>
  <div class="content">
    <input id="nameBox" placeholder="Type your name">
    <button id="greetBtn">Say hello</button>
    <div class="greeting" id="out"></div>
  </div>

  <script>
    document.getElementById('greetBtn').addEventListener('click', () => {
      const name = document.getElementById('nameBox').value;
      document.getElementById('out').textContent = 'Hello, ' + name + '!';
    });
  </script>

</body>
</html>''',
    hint: "Try changing 'Hello, ' to 'Welcome back, '.",
    challenge: 'Show a warning if the box is empty instead of greeting nobody.',
  ),
  CodeLabLesson(
    title: 'Lesson 6: Adding Items to a List',
    instruction:
        'This is the heart of a to-do app, a notes app, a shopping list. The '
        'items live in a JavaScript array, and the screen is redrawn from that '
        'array every time it changes.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .content { padding: 16px; }
    .bar { display: flex; gap: 8px; }
    input { flex: 1; padding: 12px; border: 1px solid #cbd5e1;
            border-radius: 8px; font-size: 15px; }
    button { background: #2563eb; color: white; border: none; padding: 12px 18px;
             border-radius: 8px; font-weight: 600; }
    .task { background: white; border-radius: 10px; padding: 14px;
            margin-top: 10px; box-shadow: 0 1px 4px rgba(0,0,0,0.07); }
  </style>
</head>
<body>

  <div class="topbar">My To-Do List</div>
  <div class="content">
    <div class="bar">
      <input id="taskBox" placeholder="What do you need to do?">
      <button id="addBtn">Add</button>
    </div>
    <div id="list"></div>
  </div>

  <script>
    const tasks = ['Read one chapter'];

    function draw() {
      const list = document.getElementById('list');
      list.innerHTML = '';
      tasks.forEach(task => {
        const row = document.createElement('div');
        row.className = 'task';
        row.textContent = task;
        list.appendChild(row);
      });
    }

    document.getElementById('addBtn').addEventListener('click', () => {
      const box = document.getElementById('taskBox');
      if (box.value.trim() === '') return;
      tasks.push(box.value);
      box.value = '';
      draw();
    });

    draw();
  </script>

</body>
</html>''',
    hint: 'Add another starting task inside the tasks = [ ] brackets.',
    challenge: 'Show the number of tasks above the list.',
  ),
  CodeLabLesson(
    title: 'Lesson 7: A Bottom Navigation Bar',
    instruction:
        'Phone apps put their main sections in a bar at the bottom, where your '
        'thumb reaches. Tapping a tab swaps the content above it. Tap the tabs '
        'in the preview.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .content { padding: 20px; min-height: 260px; }
    .tabs { position: fixed; bottom: 0; left: 0; right: 0; display: flex;
            background: white; border-top: 1px solid #e5e7eb; }
    .tab { flex: 1; padding: 14px; text-align: center; font-size: 14px;
           font-weight: 600; color: #94a3b8; }
    .tab.active { color: #2563eb; }
  </style>
</head>
<body>

  <div class="topbar">My App</div>
  <div class="content" id="screen">Welcome to the Home screen.</div>

  <div class="tabs">
    <div class="tab active" data-text="Welcome to the Home screen.">Home</div>
    <div class="tab" data-text="Here are your saved items.">Saved</div>
    <div class="tab" data-text="This is your profile.">Profile</div>
  </div>

  <script>
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        tabs.forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById('screen').textContent = tab.dataset.text;
      });
    });
  </script>

</body>
</html>''',
    hint: 'Change the data-text of a tab to change what that screen says.',
    challenge: 'Add a fourth tab called Settings.',
  ),
  CodeLabLesson(
    title: 'Lesson 8: A Dashboard of Numbers',
    instruction:
        'Business and school apps open on a dashboard — a few big numbers the '
        'user cares about, side by side in a grid. Change the numbers and the '
        'labels to fit an app of your own.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #16a34a; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
            padding: 16px; }
    .stat { background: white; border-radius: 12px; padding: 16px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.08); }
    .value { font-size: 26px; font-weight: 800; color: #16a34a; }
    .label { font-size: 13px; color: #64748b; margin-top: 4px; }
  </style>
</head>
<body>

  <div class="topbar">Shop Dashboard</div>
  <div class="grid">
    <div class="stat"><div class="value">42</div><div class="label">Sales today</div></div>
    <div class="stat"><div class="value">18</div><div class="label">Items left</div></div>
    <div class="stat"><div class="value">7</div><div class="label">New customers</div></div>
    <div class="stat"><div class="value">3</div><div class="label">Low stock</div></div>
  </div>

</body>
</html>''',
    hint: 'Change 1fr 1fr to 1fr to stack the cards in one column.',
    challenge: 'Add two more stat cards that matter for your own app.',
  ),
  CodeLabLesson(
    title: 'Lesson 9: Build Your Own App',
    instruction:
        'No instructions this time — this is yours. Use what you learned: a '
        'top bar, cards, a list, a button that reacts, an input box, a bottom '
        'nav. Build an app for your school, your home, or your business.',
    starterCode: '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f2f4f8; }
    .topbar { background: #2563eb; color: white; padding: 16px;
              font-size: 18px; font-weight: 700; }
    .content { padding: 16px; }
    .card { background: white; border-radius: 12px; padding: 16px;
            margin-bottom: 12px; box-shadow: 0 2px 6px rgba(0,0,0,0.08); }
    button { background: #2563eb; color: white; border: none; padding: 12px 20px;
             border-radius: 8px; font-size: 15px; font-weight: 600; }
  </style>
</head>
<body>

  <div class="topbar">My App</div>
  <div class="content">

    <div class="card">
      <h3>Start here</h3>
      <p>Change this card into the first thing your app shows.</p>
    </div>

    <button id="goBtn">Tap me</button>

  </div>

  <script>
    document.getElementById('goBtn').addEventListener('click', () => {
      alert('Your app is working!');
    });
  </script>

</body>
</html>''',
    hint: 'Stuck? Open Lesson 6 and reuse the add-to-a-list pattern.',
    challenge: 'Show your finished app to someone and ask what they would add.',
  ),
];
