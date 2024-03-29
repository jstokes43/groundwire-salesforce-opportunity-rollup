public with sharing class GW_EXT_OppTotals {
/*-----------------------------------------------------------------------------------------------
* Written by Evan Callahan, copyright (c) 2010 Groundwire
* This program is released under the GNU General Public License. http://www.gnu.org/licenses/
* 
* This class calculates opportunity fiscal year totals for display in a small VF "pagelet."
*
* Each row has Fiscal Year, # of Gifts, and Amount
* The "total" row has the word "Total" and the total for each column
-----------------------------------------------------------------------------------------------*/

	// subclass represents a row of totals for displaying in a list
	public class OppTotals {
		public string oppYear { get; set; }
		public integer oppCount { get; set; }
		public decimal oppAmount { get; set; } 
		
		OppTotals(string s) { 
			oppYear = s; 
			oppCount = 0;
			oppAmount = 0.00;
		}
	}

	// these properties allow you to display the totals in a table on the page
	public list<OppTotals> detailRows { get; set; }
	public OppTotals totalRow { get; set; }

	// use settings to limit the opp types you include in your rollups 
	set<id> recordTypesToExcludeAccts = new set<id>();
	set<id> recordTypesToExcludeCons = new set<id>();
	set<string> oppTypesToExcludeAccts = new set<string>();
	set<string> oppTypesToExcludeCons = new set<string>();	
	
	// set this to limit contact totals to opps with a specific 'bucket' account
	final string defaultAccountId = ONEN_DefaultAccount.getIndividualAccountId();

	// id of the object on the page
	id objectId;

	// constructor 
	public GW_EXT_OppTotals(ApexPages.StandardController stdController) {

		// load settings
        OppRollupSettings__c rollupSettings = OppRollupSettings__c.getInstance();

		if (rollupSettings != null) {
			if (rollupSettings.Excluded_Contact_Opp_Rectypes__c != null) {
				set<string> rtNamesToExclude = new set<string>(rollupSettings.Excluded_Contact_Opp_Rectypes__c.split(';'));
				recordTypesToExcludeCons = GW_RecTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
			}
			if (rollupSettings.Excluded_Account_Opp_Rectypes__c != null) {
				set<string> rtNamesToExclude = new set<string>(rollupSettings.Excluded_Account_Opp_Rectypes__c.split(';'));
				recordTypesToExcludeAccts = GW_RecTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
			}
			if (rollupSettings.Excluded_Contact_Opp_Types__c != null) {
				oppTypesToExcludeCons = new set<string>(rollupSettings.Excluded_Contact_Opp_Types__c.split(';'));
			}
			if (rollupSettings.Excluded_Account_Opp_Types__c != null) {
				oppTypesToExcludeAccts = new set<string>(rollupSettings.Excluded_Contact_Opp_Types__c.split(';'));
			}
		}

		detailRows = new list<OppTotals>();
		
		objectId = stdController.getId();
		if (objectId != null) {	
		
			// store the results here
			list<sObject> rollups;
			
  			if (stdController.getRecord().getSObjectType() == Account.sObjectType) { 
				rollups = [SELECT Fiscal_Year(CloseDate) FiscalYear, 
			     	SUM(Amount) TotalOppAmount, COUNT_DISTINCT(Id) NumberOfClosedOpps
			     	FROM Opportunity 
			    	WHERE isWon=true 
			    	AND (Amount > 0 OR Amount < 0) 
			    	AND RecordTypeId NOT IN : recordTypesToExcludeAccts
			    	AND Type NOT IN : oppTypesToExcludeAccts
	    			AND accountId = : objectId
					GROUP BY ROLLUP(Fiscal_Year(closeDate)) 
					ORDER BY Fiscal_Year(CloseDate) DESC ];			
 			} else if (stdController.getRecord().getSObjectType() == Contact.sObjectType) {
				rollups = [SELECT Fiscal_Year(Opportunity.CloseDate) FiscalYear, 
			     	SUM(Opportunity.Amount) TotalOppAmount, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps 
			     	FROM OpportunityContactRole 
			    	WHERE isPrimary=true AND opportunity.isWon=true 
			    	AND (Opportunity.Amount > 0 OR Opportunity.Amount < 0) 
			    	AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons
			    	AND Opportunity.Type NOT IN : oppTypesToExcludeCons
					AND (opportunity.accountid = : defaultAccountId OR opportunity.accountid = null)  
	    			AND contactId = : objectId 
					GROUP BY ROLLUP(Fiscal_Year(opportunity.closeDate)) 
					ORDER BY Fiscal_Year(Opportunity.CloseDate) DESC ];
			} else {
				rollups = [SELECT Fiscal_Year(Opportunity.CloseDate) FiscalYear, 
			     	SUM(Opportunity.Amount) TotalOppAmount, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps 
			     	FROM OpportunityContactRole 
			    	WHERE isPrimary=true AND opportunity.isWon=true 
			    	AND (Opportunity.Amount > 0 OR Opportunity.Amount < 0) 
			    	AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons
			    	AND Opportunity.Type NOT IN : oppTypesToExcludeCons
					AND (opportunity.accountid = : defaultAccountId OR opportunity.accountid = null)  
	    			AND contact.ONEN_Household__c = : objectId 
					GROUP BY ROLLUP(Fiscal_Year(opportunity.closeDate))
					ORDER BY Fiscal_Year(Opportunity.CloseDate) DESC ];
			}
	
			// the "current" year might actually be named for next year
			integer fyAdjustment = 0;
			// you can optionally comment the following 2 lines out if you know FY starts in Jan (or is named for start month)
			organization o = [select fiscalYearStartMonth, UsesStartDateAsFiscalYearName from organization limit 1];
			if (o.FiscalYearStartMonth > 1 && !o.UsesStartDateAsFiscalYearName) fyAdjustment = 1;

			// process the aggregate results
			for (sobject r : rollups) {
				system.debug('ROLLUP ROW: ' + r);

				// get the year for this row
				integer fy = (integer)(r.get('FiscalYear'));
				
				// null year means this is the totals row
				string row = (fy != null) ? string.valueOf(fy + fyAdjustment) : 'Total';
				
				// create the totals object fo this result row
				oppTotals thisRow = new oppTotals(row); 
				thisRow.oppCount = (integer)(r.get('NumberOfClosedOpps'));
				thisRow.oppAmount = (decimal)(r.get('TotalOppAmount'));
				
				// add it to the list
				if (row != 'Total') {
					detailRows.add(thisRow);
				} else {
					totalRow = thisRow;
				}
			}
		}
	}

	static testMethod void testFYTotals () {
		
		Date datClose = System.Today();
			
		// create & insert contact(s)
		Contact[] TestCons = ONEN_UnitTestData.CreateMultipleTestContacts ( 5 ) ;
		insert TestCons;

		Test.StartTest();

		// create new opps
		Opportunity[] newOpps = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datClose, 100 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS ,null);
		insert newOpps;

		account testacct = new account(name='testacct');
		insert testacct;
		id FirstConId = TestCons[4].id;
		Contact UpdatedCon = [SELECT id, account.TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, onen_household__c, TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];

		GW_EXT_OppTotals fyt;

		// create a page to test account totals
		fyt = new GW_EXT_OppTotals(new ApexPages.StandardController(testacct));

		System.AssertEquals ( 0, fyt.detailRows.size());
		System.AssertEquals ( null, fyt.totalRow);

		// create a page to test contact totals
		fyt = new GW_EXT_OppTotals(new ApexPages.StandardController(UpdatedCon));

		System.AssertEquals ( 100, fyt.detailRows[0].oppAmount);
		System.AssertEquals ( 100, fyt.totalRow.oppAmount);

		// create a page to test household totals
		fyt = new GW_EXT_OppTotals(new ApexPages.StandardController(new ONEN_Household__c(id = UpdatedCon.ONEN_Household__c)));

		System.AssertEquals ( 100, fyt.detailRows[0].oppAmount);
		System.AssertEquals ( 100, fyt.totalRow.oppAmount);

		Test.StopTest();
	}	
}