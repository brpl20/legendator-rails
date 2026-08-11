class ChangeModelUsedDefaultToLuna < ActiveRecord::Migration[8.1]
  # The old default ("gpt-4.1-mini") was not even a valid OpenRouter slug —
  # it lacks the "openai/" prefix, so any record created without an explicit
  # model would have been rejected by the API. Existing rows keep their value;
  # AiModel.find falls back to the default for retired slugs.
  def change
    change_column_default :translations, :model_used,
      from: "gpt-4.1-mini", to: "openai/gpt-5.6-luna"
  end
end
