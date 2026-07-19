import pandas as pd
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException
from bs4 import BeautifulSoup
import re
import csv
from datetime import datetime

class CadastralScraper:
    def __init__(self, csv_file_path, headless=False):
        """
        Initialize the scraper with the CSV file containing names to search
        
        Args:
            csv_file_path (str): Path to CSV file containing first_name and last_name columns
            headless (bool): Whether to run browser in headless mode
        """
        self.csv_file_path = csv_file_path
        self.headless = headless
        self.driver = None
        self.wait = None
        self.results = []
        
    def setup_driver(self):
        """Setup Chrome driver with appropriate options"""
        chrome_options = Options()
        if self.headless:
            chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1920,1080")
        
        # You may need to specify the path to your ChromeDriver
        # service = Service("/path/to/chromedriver")
        # self.driver = webdriver.Chrome(service=service, options=chrome_options)
        
        self.driver = webdriver.Chrome(options=chrome_options)
        self.wait = WebDriverWait(self.driver, 20)
        
    def load_names_from_csv(self):
        """Load names from CSV file"""
        try:
            df = pd.read_csv(self.csv_file_path)
            if 'first_name' not in df.columns or 'last_name' not in df.columns:
                raise ValueError("CSV must contain 'first_name' and 'last_name' columns")
            return df[['first_name', 'last_name']].dropna()
        except Exception as e:
            print(f"Error loading CSV: {e}")
            return None
            
    def navigate_to_website(self):
        """Navigate to the cadastral website"""
        try:
            self.driver.get("https://catastro.crimpr.net/cdprpc/")
            time.sleep(60)  # Allow page to load
            return True
        except Exception as e:
            print(f"Error navigating to website: {e}")
            return False
            
    def click_tasks_button(self):
        """Click on the Tasks button"""
        try:
            # Try multiple selectors for the Tasks button
            selectors = [
                "div.query-tab-item:nth-child(1)",
                ".query-tab-item",
                "div.query-tab-item.jimu-ellipsis.jimu-float-leading"
            ]
            
            for selector in selectors:
                try:
                    tasks_button = self.wait.until(
                        EC.element_to_be_clickable((By.CSS_SELECTOR, selector))
                    )
                    tasks_button.click()
                    time.sleep(10)
                    print("Tasks button clicked successfully")
                    return True
                except TimeoutException:
                    continue
                    
            print("Could not find Tasks button")
            return False
            
        except Exception as e:
            print(f"Error clicking Tasks button: {e}")
            return False
            
    def input_name(self, first_name, last_name):
        """Input the name into the search box"""
        try:
            # Combine first and last name with space
            full_name = f"{last_name} {first_name}".strip()
            
            # Try multiple selectors for the input box
            selectors = [
                "#dijit_form_ValidationTextBox_0",
                "input.dijitInputInner",
                "input[id*='ValidationTextBox']"
            ]
            
            for selector in selectors:
                try:
                    input_box = self.wait.until(
                        EC.presence_of_element_located((By.CSS_SELECTOR, selector))
                    )
                    
                    # Clear any existing text and input the name
                    input_box.clear()
                    input_box.send_keys(full_name)
                    time.sleep(5)
                    print(f"Entered name: {full_name}")
                    return True
                    
                except TimeoutException:
                    continue
                    
            print("Could not find input box")
            return False
            
        except Exception as e:
            print(f"Error inputting name: {e}")
            return False
            
    def click_apply_button(self):
        """Click the Apply button"""
        try:
            # Try multiple selectors for the Apply button
            selectors = [
                "div.jimu-btn.btn-execute",
                ".jimu-btn",
                "div.jimu-btn"
            ]
            
            for selector in selectors:
                try:
                    apply_button = self.wait.until(
                        EC.element_to_be_clickable((By.CSS_SELECTOR, selector))
                    )
                    apply_button.click()
                    time.sleep(5)  # Wait for results to load
                    print("Apply button clicked successfully")
                    return True
                    
                except TimeoutException:
                    continue
                    
            print("Could not find Apply button")
            return False
            
        except Exception as e:
            print(f"Error clicking Apply button: {e}")
            return False
            
    def extract_table_data(self, first_name, last_name):
        """Extract data from the results table"""
        try:
            # Wait for results to appear
            time.sleep(3)
            
            # Find the results tbody
            tbody_selectors = [
                "tbody.expanded",
                ".results-table tbody",
                "table.results-table tbody"
            ]
            
            tbody = None
            for selector in tbody_selectors:
                try:
                    tbody = self.driver.find_element(By.CSS_SELECTOR, selector)
                    break
                except NoSuchElementException:
                    continue
                    
            if not tbody:
                print("No results table found")
                return []
                
            # Find all result rows
            row_selectors = [
                ".jimu-table-row.jimu-table-row-separator.query-result-item",
                "tr.query-result-item"
            ]
            
            rows = []
            for selector in row_selectors:
                try:
                    rows = tbody.find_elements(By.CSS_SELECTOR, selector)
                    if rows:
                        break
                except NoSuchElementException:
                    continue
                    
            if not rows:
                print("No result rows found")
                return []
                
            extracted_data = []
            
            for row in rows:
                try:
                    # Get the HTML content of the row
                    row_html = row.get_attribute('outerHTML')
                    soup = BeautifulSoup(row_html, 'html.parser')
                    
                    # Extract data from the attribute table
                    attr_table = soup.find('table', class_='attrTable')
                    if attr_table:
                        row_data = {'searched_first_name': first_name, 'searched_last_name': last_name}
                        
                        # Extract all attribute name-value pairs
                        attr_rows = attr_table.find_all('tr')
                        for attr_row in attr_rows:
                            cells = attr_row.find_all('td')
                            if len(cells) >= 2:
                                attr_name = cells[0].get_text(strip=True)
                                attr_value = cells[1].get_text(strip=True)
                                
                                # Clean up the attribute name for use as column header
                                clean_attr_name = self._clean_column_name(attr_name)
                                row_data[clean_attr_name] = attr_value
                                
                        extracted_data.append(row_data)
                        
                except Exception as e:
                    print(f"Error extracting data from row: {e}")
                    continue
                    
            print(f"Extracted {len(extracted_data)} records")
            return extracted_data
            
        except Exception as e:
            print(f"Error extracting table data: {e}")
            return []
            
    def _clean_column_name(self, name):
        """Clean column names for CSV export"""
        # Remove special characters and replace spaces with underscores
        clean_name = re.sub(r'[^\w\s]', '', name)
        clean_name = re.sub(r'\s+', '_', clean_name)
        return clean_name.lower()
        
    def search_person(self, first_name, last_name):
        """Complete search process for one person"""
        print(f"\nSearching for: {first_name} {last_name}")
        
        try:
            # Navigate to website (if not already there)
            #if not self.navigate_to_website():
               # return []
                
            # Click Tasks button
            if not self.click_tasks_button():
                return []
                
            # Input name
            if not self.input_name(first_name, last_name):
                return []
                
            # Click Apply
            if not self.click_apply_button():
                return []
            time.sleep(10)
                
            # Extract results
            results = self.extract_table_data(first_name, last_name)
            
            return results
            
        except Exception as e:
            print(f"Error searching for {first_name} {last_name}: {e}")
            return []
            
    def run_scraper(self):
        """Main method to run the scraping process"""
        try:
            # Load names from CSV
            names_df = self.load_names_from_csv()
            if names_df is None:
                return
                
            print(f"Loaded {len(names_df)} names to search")
            
            # Setup driver
            self.setup_driver()
            self.navigate_to_website()
                         
            # Process each name
            all_results = []
            
            for index, row in names_df.iterrows():
                first_name = str(row['first_name']).strip()
                last_name = str(row['last_name']).strip()
                
                if pd.isna(first_name) or pd.isna(last_name):
                    continue
                    
                results = self.search_person(first_name, last_name)
                all_results.extend(results)
                
                # Add a small delay between searches to be respectful
                time.sleep(5)
                
            # Save results to CSV
            if all_results:
                self.save_results_to_csv(all_results)
            else:
                print("No results found")
                
        except Exception as e:
            print(f"Error running scraper: {e}")
            
        finally:
            if self.driver:
                self.driver.quit()
                
    def save_results_to_csv(self, results):
        """Save results to CSV file"""
        try:
            if not results:
                print("No results to save")
                return
                
            # Create DataFrame from results
            df = pd.DataFrame(results)
            
            # Generate output filename with timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_filename = f"cadastral_results_{timestamp}.csv"
            
            # Save to CSV
            df.to_csv(output_filename, index=False, encoding='utf-8')
            print(f"Results saved to: {output_filename}")
            print(f"Total records: {len(results)}")
            
        except Exception as e:
            print(f"Error saving results: {e}")

def main():
    """Main function to run the scraper"""
    # Configuration
    CSV_FILE_PATH = "Input/names_individuos22.csv"  # Update this path to your CSV file
    HEADLESS_MODE = False  # Set to True to run without browser window
    
    # Create and run scraper
    scraper = CadastralScraper(CSV_FILE_PATH, headless=HEADLESS_MODE)
    scraper.run_scraper()

if __name__ == "__main__":
    main()
