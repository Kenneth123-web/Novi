import SwiftUI

/// One question at a time, graded server-side.
///
/// The client never receives the answer key until it has submitted — the
/// question payload simply does not contain it. Feedback appears per question
/// after the whole set is submitted, which is what keeps a single request
/// authoritative for the score.
struct QuizView: View {
    let conceptID: UUID
    let conceptName: String

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var quiz: QuizDTO?
    @State private var index = 0
    @State private var selections: [UUID: Int] = [:]
    @State private var result: QuizResultDTO?
    @State private var loading = true
    @State private var submitting = false
    @State private var error: APIError?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    ResultView(result: result, conceptName: conceptName) { dismiss() }
                } else if loading {
                    loadingState
                } else if let error {
                    errorState(error)
                } else if let quiz, index < quiz.questions.count {
                    questionState(quiz)
                } else {
                    ProgressView()
                }
            }
            .background(NV.page)
            .navigationTitle(conceptName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.foregroundStyle(NV.inkSoft)
                }
            }
        }
        .task { await generate() }
    }

    private var loadingState: some View {
        VStack(spacing: NV.Space.l) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Writing your questions…")
                .font(NV.small).foregroundStyle(NV.inkFaint)
            Spacer()
        }
    }

    private func errorState(_ error: APIError) -> some View {
        VStack(spacing: NV.Space.l) {
            Spacer()
            NVEmptyState(
                icon: error.isAIUnavailable ? "sparkles" : "exclamationmark.triangle",
                title: error.isAIUnavailable ? "The tutor is offline" : "Couldn't build a quiz",
                message: error.message,
                actionTitle: "Try again",
                action: { Task { await generate() } }
            )
            Spacer()
        }
    }

    private func questionState(_ quiz: QuizDTO) -> some View {
        let question = quiz.questions[index]
        return VStack(alignment: .leading, spacing: NV.Space.l) {
            NVStepBar(step: index, total: quiz.questions.count)
                .padding(.horizontal, NV.Space.l)

            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.l) {
                    Text("Question \(index + 1) of \(quiz.questions.count)")
                        .font(NV.caption).foregroundStyle(NV.inkFaint)
                    Text(question.prompt)
                        .font(NV.h2)
                        .foregroundStyle(NV.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: NV.Space.s) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                            optionRow(option, index: i, question: question)
                        }
                    }
                }
                .padding(.horizontal, NV.Space.l)
                .padding(.top, NV.Space.s)
            }

            NVButton(
                title: index == quiz.questions.count - 1 ? "Submit" : "Next",
                loading: submitting,
                enabled: selections[question.id] != nil
            ) {
                if index == quiz.questions.count - 1 {
                    Task { await submit() }
                } else {
                    withAnimation { index += 1 }
                }
            }
            .padding(.horizontal, NV.Space.l)
            .padding(.bottom, NV.Space.l)
        }
    }

    private func optionRow(_ option: String, index i: Int, question: QuizQuestionDTO) -> some View {
        let selected = selections[question.id] == i
        return Button {
            selections[question.id] = i
        } label: {
            HStack(spacing: NV.Space.m) {
                Text(["A", "B", "C", "D"][min(i, 3)])
                    .font(NV.caption.weight(.bold))
                    .foregroundStyle(selected ? .white : NV.inkFaint)
                    .frame(width: 26, height: 26)
                    .background(selected ? NV.accent : NV.fill, in: Circle())
                Text(option)
                    .font(NV.body)
                    .foregroundStyle(NV.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(NV.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(NV.Radius.control)
            .overlay {
                RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous)
                    .stroke(selected ? NV.accent : NV.hairline, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    // MARK: Actions

    private func generate() async {
        loading = true
        error = nil
        do {
            quiz = try await session.api.authed(
                .post, "quiz",
                body: QuizBody(conceptId: conceptID.uuidString, count: 5),
                as: QuizDTO.self
            )
            index = 0
            selections = [:]
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        loading = false
    }

    private func submit() async {
        guard let quiz else { return }
        submitting = true
        do {
            result = try await session.api.authed(
                .post, "quiz/\(quiz.id)/submit",
                body: QuizSubmitBody(
                    answers: selections.map {
                        QuizAnswerBody(questionId: $0.key.uuidString, selectedIndex: $0.value)
                    }
                ),
                as: QuizResultDTO.self
            )
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        submitting = false
    }
}

/// The score, what was wrong and why, and anything newly earned.
private struct ResultView: View {
    let result: QuizResultDTO
    let conceptName: String
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: NV.Space.xl) {
                score

                if !result.newStamps.isEmpty { stamps }

                VStack(alignment: .leading, spacing: NV.Space.s) {
                    Text("REVIEW").font(NV.caption).foregroundStyle(NV.inkFaint)
                    ForEach(Array(result.answers.enumerated()), id: \.element.id) { i, answer in
                        answerRow(i, answer)
                    }
                }

                NVButton(title: "Done", action: onDone)
            }
            .padding(NV.Space.l)
        }
    }

    private var score: some View {
        VStack(spacing: NV.Space.s) {
            Text("\(Int(result.score * 100))%")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(result.score >= 0.8 ? NV.success : NV.accent)
            Text("\(result.correct) of \(result.total) correct")
                .font(NV.body).foregroundStyle(NV.inkSoft)

            NVProgressBar(
                value: result.score,
                tint: result.score >= 0.8 ? NV.success : NV.accent,
                height: 8
            )
            .padding(.horizontal, NV.Space.xxl)
            .padding(.top, NV.Space.xs)

            HStack(spacing: 6) {
                Image(systemName: "seal.fill").font(.system(size: 11))
                Text("\(conceptName) — \(result.conceptMastery.capitalized)")
                    .font(NV.small.weight(.medium))
            }
            .foregroundStyle(NV.mastery(result.conceptMastery))
            .padding(.top, NV.Space.xs)
        }
        .padding(.top, NV.Space.l)
    }

    private var stamps: some View {
        VStack(spacing: NV.Space.s) {
            Text("ADDED TO YOUR PASSPORT").font(NV.caption).foregroundStyle(NV.accent)
            HStack(spacing: NV.Space.m) {
                ForEach(result.newStamps) { stamp in
                    StampBadge(
                        title: stamp.title, subtitle: stamp.subtitle, icon: stamp.icon
                    )
                }
            }
        }
        .padding(NV.Space.l)
        .frame(maxWidth: .infinity)
        .background(NV.accentSoft,
                    in: RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous))
    }

    private func answerRow(_ i: Int, _ answer: GradedAnswerDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: answer.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(answer.isCorrect ? NV.success : NV.error)
                Text("Question \(i + 1)").font(NV.caption).foregroundStyle(NV.inkFaint)
                Spacer(minLength: 0)
                if !answer.isCorrect {
                    Text("Answer: \(["A", "B", "C", "D"][min(answer.correctIndex, 3)])")
                        .font(NV.caption.weight(.semibold))
                        .foregroundStyle(NV.success)
                }
            }
            if !answer.explanation.isEmpty {
                Text(answer.explanation)
                    .font(NV.small)
                    .foregroundStyle(NV.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NV.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(NV.Radius.control)
    }
}

/// A collectible stamp. Rotated slightly and drawn with a dashed rule so it
/// reads as something pressed into a passport rather than a list row.
struct StampBadge: View {
    let title: String
    var subtitle: String = ""
    var icon: String = "seal"
    var tint: Color = NV.accent

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
            Text(title)
                .font(NV.caption.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            if !subtitle.isEmpty {
                Text(subtitle.uppercased())
                    .font(.system(size: 7.5, weight: .semibold))
                    .opacity(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        // Inset from the circle's edge: text laid out to the full diameter
        // overflows the curve at the top and bottom of its own line box.
        .padding(.horizontal, 14)
        .foregroundStyle(tint)
        .frame(width: 104, height: 104)
        .background(
            Circle().fill(NV.surface)
        )
        .overlay(
            Circle().strokeBorder(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        )
        .rotationEffect(.degrees(-6))
    }
}
