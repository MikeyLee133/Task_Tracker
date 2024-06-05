import SwiftUI
import UserNotifications

// Define a data model for tasks
struct Task: Identifiable, Codable {
    let id = UUID()
    var title: String
    var dueDate: Date?
    var isCompleted: Bool = false
    var groupId: UUID? // Group identifier

    enum CodingKeys: String, CodingKey {
        case id, title, dueDate, isCompleted, groupId
    }
}

// ViewModel for managing tasks
class TaskViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var newTaskTitle: String = ""
    @Published var selectedDate = Date()
    @Published var selectedGroupId: UUID? = nil

    private let tasksKey = "tasks"

    init() {
        fetchTasks()
    }

    func fetchTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let savedTasks = try? JSONDecoder().decode([Task].self, from: data) {
            tasks = savedTasks
        }
    }

    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksKey)
        }
    }

    func scheduleNotification(for task: Task) {
        guard let dueDate = task.dueDate else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = "Don't forget to \(task.title)!"
        content.sound = UNNotificationSound.default

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Notification scheduled successfully")
            }
        }
    }

    func addTask() {
        guard !newTaskTitle.isEmpty else { return }

        let newTask = Task(title: newTaskTitle, dueDate: selectedDate, groupId: selectedGroupId)
        tasks.append(newTask)
        scheduleNotification(for: newTask)
        saveTasks()
        newTaskTitle = ""
    }

    func toggleTaskCompletion(for task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
            saveTasks()
        }
    }

    func deleteTask(task: Task) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }

    func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            let task = tasks[index]
            deleteTask(task: task)
        }
    }

    func updateTask(task: Task, newTitle: String, newDueDate: Date?) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].title = newTitle
            tasks[index].dueDate = newDueDate
            saveTasks()
        }
    }
}

// Main content view
struct ContentView: View {
    @StateObject private var viewModel = TaskViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    TaskSectionView(title: "Today", tasks: viewModel.tasks.filter { isToday($0.dueDate) }, viewModel: viewModel)
                    TaskSectionView(title: "Upcoming", tasks: viewModel.tasks.filter { isUpcoming($0.dueDate) }, viewModel: viewModel)
                    TaskSectionView(title: "Overdue", tasks: viewModel.tasks.filter { isOverdue($0.dueDate) }, viewModel: viewModel)
                }
                .listStyle(PlainListStyle())
                
                Divider()
                
                HStack(spacing: 20) {
                    TextField("Add a new task", text: $viewModel.newTaskTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                    
                    DatePicker("Due Date", selection: $viewModel.selectedDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .frame(width: 180)
                    
                    Button(action: {
                        viewModel.addTask()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 10)
                .background(Color.white)
                .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 2)
            }
            .navigationTitle("Task Tracker")
        }
        .background(Color(UIColor.systemGray6).ignoresSafeArea())
    }
}

// Custom task section view
struct TaskSectionView: View {
    let title: String
    var tasks: [Task]
    let viewModel: TaskViewModel

    var body: some View {
        if !tasks.isEmpty {
            Section(header: Text(title).font(.headline)) {
                ForEach(tasks.sorted(by: { $0.dueDate ?? .distantFuture < $1.dueDate ?? .distantFuture }), id: \.id) { task in
                    TaskRow(task: task,
                            toggleTaskCompletion: viewModel.toggleTaskCompletion,
                            deleteTask: { viewModel.deleteTask(task: task) },
                            updateTask: viewModel.updateTask)
                }
                .onDelete(perform: { indexSet in
                    viewModel.deleteTasks(at: indexSet)
                })
            }
        }
    }
}


// Custom task row view
struct TaskRow: View {
    let task: Task
    let toggleTaskCompletion: (Task) -> Void
    let deleteTask: () -> Void
    let updateTask: (Task, String, Date?) -> Void

    @State private var isEditing: Bool = false
    @State private var editedTitle: String
    @State private var editedDueDate: Date

    init(task: Task, toggleTaskCompletion: @escaping (Task) -> Void, deleteTask: @escaping () -> Void, updateTask: @escaping (Task, String, Date?) -> Void) {
        self.task = task
        self.toggleTaskCompletion = toggleTaskCompletion
        self.deleteTask = deleteTask
        self.updateTask = updateTask

        _editedTitle = State(initialValue: task.title)
        _editedDueDate = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        HStack {
            if isEditing {
                TextField("Edit task", text: $editedTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .onAppear {
                        editedTitle = task.title
                        editedDueDate = task.dueDate ?? Date()
                    }

                DatePicker("Due Date", selection: $editedDueDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .frame(height: 50)
                    .padding(.horizontal)

                Button(action: {
                    updateTask(task, editedTitle, editedDueDate)
                    isEditing = false
                }) {
                    Text("Save")
                }
                .padding(.horizontal)
            } else {
                Button(action: {
                    toggleTaskCompletion(task)
                }) {
                    Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundColor(task.isCompleted ? .green : .primary)
                }
                .buttonStyle(BorderlessButtonStyle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundColor(task.isCompleted ? .gray : .primary)

                    if let dueDate = task.dueDate {
                        Text("Due: \(formattedDateString(from: dueDate))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 20) {
                    Button(action: {
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    Button(action: {
                        deleteTask()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.trailing)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
        .shadow(color: .gray.opacity(0.5), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }

    private func formattedDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Helper functions to categorize tasks by date
func isToday(_ date: Date?) -> Bool {
    guard let date = date else { return false }
    return Calendar.current.isDateInToday(date)
}

func isUpcoming(_ date: Date?) -> Bool {
    guard let date = date else { return false }
    return Calendar.current.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
}

func isOverdue(_ date: Date?) -> Bool {
    guard let date = date else { return false }
    return Calendar.current.compare(date, to: Date(), toGranularity: .day) == .orderedAscending
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
