import os
import logging
from datetime import datetime
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
from aiogram.types import ReplyKeyboardMarkup, KeyboardButton, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.storage.memory import MemoryStorage
from dotenv import load_dotenv
from database import Database
import tempfile

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)

# Initialize bot and dispatcher
bot = Bot(token=os.getenv("BOT_TOKEN"))
storage = MemoryStorage()
dp = Dispatcher(storage=storage)
db = Database()

# States
class BloodPressure(StatesGroup):
    waiting_for_systolic = State()
    waiting_for_diastolic = State()
    waiting_for_pulse = State()

# Keyboards
def get_main_keyboard():
    keyboard = ReplyKeyboardMarkup(
        keyboard=[
            [KeyboardButton(text="📝 Добавить измерение")],
            [KeyboardButton(text="📊 История измерений")],
        ],
        resize_keyboard=True
    )
    return keyboard

def get_history_keyboard():
    keyboard = ReplyKeyboardMarkup(
        keyboard=[
            [KeyboardButton(text="📊 Статистика")],
            [KeyboardButton(text="📥 Экспорт данных")],
            [KeyboardButton(text="⬅️ Назад")],
        ],
        resize_keyboard=True
    )
    return keyboard

@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    await message.answer(
        "👋 Привет! Я бот для отслеживания артериального давления.\n\n"
        "💪 Я помогу вам вести дневник измерений давления и пульса.\n"
        "🎯 Используйте кнопки ниже для управления:",
        reply_markup=get_main_keyboard()
    )

@dp.message(lambda message: message.text == "📝 Добавить измерение")
async def add_measurement(message: types.Message, state: FSMContext):
    await message.answer("🔝 Введите верхнее (систолическое) давление:")
    await state.set_state(BloodPressure.waiting_for_systolic)

@dp.message(BloodPressure.waiting_for_systolic)
async def process_systolic(message: types.Message, state: FSMContext):
    try:
        systolic = int(message.text)
        if not (60 <= systolic <= 250):
            raise ValueError
        await state.update_data(systolic=systolic)
        await message.answer("🔻 Введите нижнее (диастолическое) давление:")
        await state.set_state(BloodPressure.waiting_for_diastolic)
    except ValueError:
        await message.answer("⚠️ Пожалуйста, введите корректное значение (от 60 до 250):")

@dp.message(BloodPressure.waiting_for_diastolic)
async def process_diastolic(message: types.Message, state: FSMContext):
    try:
        diastolic = int(message.text)
        if not (40 <= diastolic <= 150):
            raise ValueError
        await state.update_data(diastolic=diastolic)
        await message.answer("💓 Введите пульс:")
        await state.set_state(BloodPressure.waiting_for_pulse)
    except ValueError:
        await message.answer("⚠️ Пожалуйста, введите корректное значение (от 40 до 150):")

@dp.message(BloodPressure.waiting_for_pulse)
async def process_pulse(message: types.Message, state: FSMContext):
    try:
        pulse = int(message.text)
        if not (40 <= pulse <= 200):
            raise ValueError
        
        data = await state.get_data()
        current_time = datetime.now()
        
        # Save to database
        db.add_measurement(message.from_user.id, data['systolic'], data['diastolic'], pulse)
        
        await message.answer(
            f"✅ Измерение сохранено:\n\n"
            f"🕒 Дата и время: {current_time.strftime('%d-%m-%Y %H:%M')}\n"
            f"📊 Давление: {data['systolic']}/{data['diastolic']}\n"
            f"💓 Пульс: {pulse}",
            reply_markup=get_main_keyboard()
        )
        await state.clear()
    except ValueError:
        await message.answer("⚠️ Пожалуйста, введите корректное значение пульса (от 40 до 200):")

@dp.message(lambda message: message.text == "📊 История измерений")
async def show_history(message: types.Message):
    measurements = db.get_user_measurements(message.from_user.id)
    
    if not measurements:
        await message.answer(
            "📭 У вас пока нет сохраненных измерений.",
            reply_markup=get_main_keyboard()
        )
        return
    
    history_text = "📋 Последние измерения:\n\n"
    for systolic, diastolic, pulse, timestamp in measurements:
        # Convert string timestamp to datetime object
        dt = datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S.%f')
        history_text += (
            f"🕒 Дата: {dt.strftime('%d-%m-%Y %H:%M')}\n"
            f"📊 Давление: {systolic}/{diastolic}\n"
            f"💓 Пульс: {pulse}\n"
            f"{'─' * 20}\n"
        )
    
    await message.answer(
        history_text,
        reply_markup=get_history_keyboard()
    )

@dp.message(lambda message: message.text == "📊 Статистика")
async def show_statistics(message: types.Message):
    stats = db.get_user_statistics(message.from_user.id)
    
    if not stats["averages"]["systolic"]:
        await message.answer(
            "📭 Недостаточно данных для отображения статистики.",
            reply_markup=get_history_keyboard()
        )
        return
    
    stats_text = "📈 Статистика измерений:\n\n"
    
    # Averages
    stats_text += "📊 Средние значения:\n"
    stats_text += f"💪 Давление: {stats['averages']['systolic']}/{stats['averages']['diastolic']}\n"
    stats_text += f"💓 Пульс: {stats['averages']['pulse']}\n\n"
    
    # Min/Max
    stats_text += "📉 Минимальные значения:\n"
    stats_text += f"💪 Давление: {stats['min_max']['systolic']['min']}/{stats['min_max']['diastolic']['min']}\n"
    stats_text += f"💓 Пульс: {stats['min_max']['pulse']['min']}\n\n"
    
    stats_text += "📈 Максимальные значения:\n"
    stats_text += f"💪 Давление: {stats['min_max']['systolic']['max']}/{stats['min_max']['diastolic']['max']}\n"
    stats_text += f"💓 Пульс: {stats['min_max']['pulse']['max']}"
    
    await message.answer(
        stats_text,
        reply_markup=get_history_keyboard()
    )

@dp.message(lambda message: message.text == "📥 Экспорт данных")
async def export_data(message: types.Message):
    measurements = db.get_all_user_measurements(message.from_user.id)
    
    if not measurements:
        await message.answer(
            "📭 У вас пока нет сохраненных измерений.",
            reply_markup=get_history_keyboard()
        )
        return
    
    # Create temporary file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as temp_file:
        # Write header
        temp_file.write("Дневник измерений артериального давления\n")
        temp_file.write("=" * 40 + "\n\n")
        
        # Write measurements
        for systolic, diastolic, pulse, timestamp in measurements:
            dt = datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S.%f')
            temp_file.write(f"Дата и время: {dt.strftime('%d-%m-%Y %H:%M')}\n")
            temp_file.write(f"Давление: {systolic}/{diastolic}\n")
            temp_file.write(f"Пульс: {pulse}\n")
            temp_file.write("-" * 40 + "\n")
    
    # Send file
    with open(temp_file.name, 'rb') as file:
        await message.answer_document(
            document=types.FSInputFile(file.name, filename="blood_pressure_measurements.txt"),
            caption="📥 Ваши измерения экспортированы в текстовый файл",
            reply_markup=get_history_keyboard()
        )
    
    # Clean up
    os.unlink(temp_file.name)

@dp.message(lambda message: message.text == "⬅️ Назад")
async def back_to_main(message: types.Message):
    await message.answer(
        "🏠 Главное меню:",
        reply_markup=get_main_keyboard()
    )

async def main():
    await dp.start_polling(bot)

if __name__ == "__main__":
    import asyncio
    asyncio.run(main()) 