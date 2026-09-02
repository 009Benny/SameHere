//
//  MyThoughtsView.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import SwiftUI

struct MyThoughtsView : View {
    @StateObject private var viewModel = MyThoughtsViewModel()
    @Namespace private var animation
    @State private var showCreateSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()
                VStack{
                    List{
                        ForEach(viewModel.thoughts) { thought in
                            NavigationLink(value: thought) {
                                Text(thought.message)
                                    .matchedGeometryEffect(id: "background_\(thought.id)", in: animation)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    
                }
                .navigationTitle("My own ideas")
                .navigationDestination(for: Thought.self, destination: { thought in
                    ThoughView(
                        thought: thought,
                        isFullScreen: true,
                        isDetail: true,
                        animation: animation
                    )
                })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("+", action: {
                            showCreateSheet = true
                        })
                    }
                }
                .sheet(isPresented: $showCreateSheet) {
                    CreateThoughSheet(viewModel: viewModel)
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
    
}

struct CreateOptionItem: Identifiable {
    let id = UUID()
    var text: String = ""
}

struct CreateThoughSheet: View {
    @ObservedObject var viewModel: MyThoughtsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var options = [CreateOptionItem(), CreateOptionItem()]
    
    private var isFormValid: Bool {
        let isMessageValid = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let areOptionsValid = options.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        return isMessageValid && areOptionsValid && options.count >= 2
    }
    
    var body: some View {
        NavigationStack{
            Form {
                Section(header: Text("Tell us your thought")) {
                    TextField("Thought", text: $message)
                }
                Section(
                    header: Text("Options"),
                    footer: Text("It should have at least two options.")
                ) {
                    ForEach($options) { $option in
                        TextField("...", text: $option.text)
                    }
                    .onDelete(perform: deleteOption(at:))
                    
                    Button(action: {
                        withAnimation {
                            options.append(CreateOptionItem())
                        }
                    }) {
                        Label("Add option", systemImage: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Create a thought")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .tint(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveIdea()
                        dismiss()
                    }
                    .tint(.blue)
                    .disabled(!isFormValid)
                }
            }
        }
    }
    
    private func deleteOption(at offsets: IndexSet) {
        options.remove(atOffsets: offsets)
        if options.count < 2 {
            options.append(CreateOptionItem())
        }
    }
    
    private func saveIdea() {
        let finalOptions = options.map { $0.text }
        print(finalOptions)
//        viewModel.saveThought(message: message, topic: finalTopic, options: finalOptions)
    }
    
}

#Preview {
    MyThoughtsView()
}
